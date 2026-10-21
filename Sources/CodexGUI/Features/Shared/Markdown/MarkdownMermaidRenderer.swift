import AppKit
import ImageIO
import WebKit

/// Prepares offline Mermaid pixels for Markdown without blocking AppKit's event loop.
@MainActor
enum MarkdownMermaidRenderer
{
	struct Diagnostic: Sendable, CustomStringConvertible
	{
		let phase: String
		let reason: String
		let elapsed: Duration
		let errorDomain: String?
		let errorCode: Int?

		var description: String
		{
			let failure = errorDomain.map
			{
				" \($0):\(errorCode ?? 0)"
			} ?? ""
			return "\(phase): \(reason) after \(elapsed)\(failure)"
		}
	}

	static let maximumPreparedPixels = 16_000_000
	static let transcriptMaximumPreparedPixels = 2_000_000
	// Leave the shared renderer room for local images and math earlier in the document.
	private static let filePreviewReservePixels = 4_000_000
	private static let maximumDiagramPixels = 2_000_000
	private static var occupied = false
	private static var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []
	private static var retainedSession: Session?
	private static let imageCache = MarkdownRichBlockImageCache()

	static func prepare(
		parsed: ParsedMarkdownContent,
		maximumPreparedPixels: Int = MarkdownMermaidRenderer.maximumPreparedPixels,
		onDiagnostic: (@MainActor (Diagnostic) -> Void)? = nil
	) async
		-> [Data: MarkdownRichBlockImageCache.Images]
	{
		var sources: [String] = []
		var seen = Set<Data>()
		for run in parsed.runs
		{
			guard let block = run.style.richBlock, block.kind == .diagram,
					admits(block.payload), seen.insert(Data(block.payload.utf8)).inserted
			else
			{
				continue
			}
			sources.append(block.payload)
			if sources.count == 32
			{
				break
			}
		}
		guard !sources.isEmpty
		else
		{
			return [:]
		}
		guard maximumPreparedPixels > 16_384
		else
		{
			return [:]
		}
		guard await acquire()
		else
		{
			onDiagnostic?(Diagnostic(
				phase: "admission",
				reason: Task.isCancelled ? "cancelled" : "queue full",
				elapsed: .zero,
				errorDomain: nil,
				errorCode: nil
			))
			return [:]
		}
		defer
		{
			release()
		}
		let session: Session
		if let existing = retainedSession, existing.isValid
		{
			session = existing
		}
		else
		{
			session = Session(onDiagnostic: onDiagnostic)
		}
		retainedSession = session
		session.setDiagnostics(onDiagnostic)
		defer
		{
			session.setDiagnostics(nil)
			if !session.isValid
			{
				retainedSession = nil
			}
		}
		if !session.isLoaded
		{
			guard await session.load()
			else
			{
				session.invalidate()
				return [:]
			}
		}
		var images: [Data: MarkdownRichBlockImageCache.Images] = [:]
		let reserve = min(
			filePreviewReservePixels,
			maximumPreparedPixels / 4
		)
		var remainingPixels = max(
			0,
			maximumPreparedPixels - reserve
		)
		for (index, source) in sources.enumerated()
		{
			guard !Task.isCancelled, session.isValid, remainingPixels > 16_384
			else
			{
				break
			}
			let allowance = min(
				maximumDiagramPixels,
				remainingPixels / ((sources.count - index) * 2)
			)
			let key = MarkdownRichBlockImageCache.Key(
				kind: .diagram,
				payload: Data(source.utf8),
				parameters: [CGFloat(allowance)]
			)
			if let cached = imageCache.images(for: key),
				cached.budgetPixelCost <= remainingPixels
			{
				remainingPixels -= cached.budgetPixelCost
				images[key.payload] = cached
				continue
			}
			guard let light = await session.render(
				source,
				dark: false,
				maximumPixels: allowance
			), !Task.isCancelled, let dark = await session.render(
				source,
				dark: true,
				maximumPixels: allowance
			)
			else
			{
				continue
			}
			let pair = MarkdownRichBlockImageCache.Images(
				light: light.image,
				dark: dark.image,
				lightSize: light.size,
				darkSize: dark.size
			)
			guard pair.budgetPixelCost <= remainingPixels
			else
			{
				continue
			}
			remainingPixels -= pair.budgetPixelCost
			images[key.payload] = pair
			imageCache.insert(
				pair,
				for: key
			)
		}
		return Task.isCancelled ? [:] : images
	}

	static func admits(_ source: String) -> Bool
	{
		!source.isEmpty && source.utf16.count <= 8_192
			&& source.components(separatedBy: .newlines).count <= 256
			&& !source.unicodeScalars.contains
			{
				CharacterSet.newlines.contains($0) && $0.value != 10 && $0.value != 13
			}
	}

	private static func acquire() async -> Bool
	{
		guard !Task.isCancelled
		else
		{
			return false
		}
		if !occupied
		{
			occupied = true
			return true
		}
		guard waiters.count < 8
		else
		{
			return false
		}
		let id = UUID()
		return await withTaskCancellationHandler
		{
			await withCheckedContinuation
			{
				continuation in
				if Task.isCancelled
				{
					continuation.resume(returning: false)
				}
				else
				{
					waiters.append((id, continuation))
				}
			}
		} onCancel:
		{
			Task
			{
				@MainActor in
				guard let index = waiters.firstIndex(where:
					{
						$0.0 == id
					})
				else
				{
					return
				}
				waiters.remove(at: index).1.resume(returning: false)
			}
		}
	}

	private static func release()
	{
		if waiters.isEmpty
		{
			occupied = false
		}
		else
		{
			waiters.removeFirst().1.resume(returning: true)
		}
	}

	/// One isolated web process page per admitted preparation; every operation has one completion.
	@MainActor
	private final class Session: NSObject, WKNavigationDelegate
	{
		struct Raster: Sendable
		{
			let image: CGImage
			let size: NSSize
		}

		private let webView: WKWebView
		private var continuation: CheckedContinuation<Raster?, Never>?
		private var timeout: Task<Void, Never>?
		private var pageReadinessProbe: MarkdownMermaidPageReadinessProbe?
		private var operationID: UUID?
		private var phase = "page"
		private var operationStarted = ContinuousClock.now
		private var onDiagnostic: (@MainActor (Diagnostic) -> Void)?
		private var loaded = false
		private(set) var isValid = true
		var isLoaded: Bool
		{
			loaded
		}

		init(onDiagnostic: (@MainActor (Diagnostic) -> Void)?)
		{
			self.onDiagnostic = onDiagnostic
			let configuration = WKWebViewConfiguration()
			configuration.websiteDataStore = .nonPersistent()
			configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
			webView = WKWebView(
				frame: NSRect(
					x: 0,
					y: 0,
					width: 1_200,
					height: 800
				),
				configuration: configuration
			)
			super.init()
			webView.navigationDelegate = self
		}

		func setDiagnostics(_ callback: (@MainActor (Diagnostic) -> Void)?)
		{
			onDiagnostic = callback
		}

		func load() async -> Bool
		{
			guard let page = Bundle.module.url(
				forResource: "index",
				withExtension: "html",
				subdirectory: "Mermaid"
			)
			else
			{
				report("missing resource")
				return false
			}
			_ = await performOperation(phase: "page")
			{
				_ in
				webView.loadFileURL(
					page,
					allowingReadAccessTo: page.deletingLastPathComponent()
				)
			}
			return loaded && !Task.isCancelled
		}

		func render(
			_ source: String,
			dark: Bool,
			maximumPixels: Int
		) async -> Raster?
		{
			guard loaded, isValid, !Task.isCancelled
			else
			{
				return nil
			}
			return await performOperation(phase: dark ? "dark raster" : "light raster")
			{
				id in
				webView.callAsyncJavaScript(
					"return await renderMarkdownDiagram(source, dark, maximumPixels);",
					arguments: ["source": source, "dark": dark, "maximumPixels": maximumPixels],
					in: nil,
					in: .page
				)
				{
					[weak self] result in
					guard let self, operationID == id
					else
					{
						return
					}
					var raster: Raster?
					if case let .failure(error) = result
					{
						report(
							"JavaScript failed",
							error: error
						)
					}
					if case let .success(value) = result,
						let values = value as? [String: Any],
						let naturalWidth = values["naturalWidth"] as? Double,
						let naturalHeight = values["naturalHeight"] as? Double,
						naturalWidth.isFinite, naturalHeight.isFinite,
						naturalWidth > 0, naturalHeight > 0,
						naturalWidth <= 900, naturalHeight <= 1_800,
						let png = values["png"] as? String,
						png.hasPrefix("data:image/png;base64,"), png.utf8.count <= 16_000_000,
						let data = Data(base64Encoded: String(png.dropFirst(22))),
						let decoded = CGImageSourceCreateWithData(
						data as CFData,
						nil
						)
					{
						if let image = CGImageSourceCreateImageAtIndex(
							decoded,
							0,
							nil
						), image.width <= 4_096, image.height <= 4_096,
						image.width * image.height <= maximumPixels
						{
							raster = Raster(
								image: image,
								size: NSSize(
									width: naturalWidth,
									height: naturalHeight
								)
							)
						}
					}
					if raster == nil, case .success = result
					{
						report("invalid raster result")
					}
					finish(raster)
				}
			}
		}

		private func performOperation(
			phase: String,
			_ start: (UUID) -> Void
		) async -> Raster?
		{
			guard isValid, !Task.isCancelled
			else
			{
				return nil
			}
			return await withTaskCancellationHandler
			{
				await withCheckedContinuation
				{
					continuation in
					self.continuation = continuation
					let id = UUID()
					self.phase = phase
					operationStarted = .now
					operationID = id
					timeout = Task
					{
						try? await Task.sleep(for: .seconds(5))
						guard !Task.isCancelled, operationID == id
						else
						{
							return
						}
						deadlineExpired(for: id)
					}
					start(id)
				}
			} onCancel:
			{
				Task
				{
					@MainActor [weak self] in
					self?.invalidate()
				}
			}
		}

		private func deadlineExpired(for id: UUID)
		{
			guard phase == "page"
			else
			{
				report("operation timed out")
				invalidate()
				return
			}
			// A busy MainActor can deliver its timer before WebKit's already-finished navigation.
			// Check the guest's actual readiness instead of discarding that completed page.
			report("page deadline checking readiness")
			let probe = MarkdownMermaidPageReadinessProbe(
				probe:
				{
					[weak self] completion in
					guard let self, operationID == id, isValid
					else
					{
						completion(false)
						return
					}
					webView.evaluateJavaScript(
						"document.readyState === 'complete' && "
							+ "typeof renderMarkdownDiagram === 'function'"
					)
					{
						[weak self] value, error in
						if let error
						{
							self?.report(
								"page readiness probe failed",
								error: error
							)
						}
						completion(error == nil && value as? Bool == true)
					}
				},
				completion:
				{
					[weak self] ready in
					guard let self, operationID == id, isValid
					else
					{
						return
					}
					if ready
					{
						loaded = true
						report("page readiness confirmed after deadline")
						finish(nil)
					}
					else
					{
						report("page operation timed out")
						invalidate()
					}
				}
			)
			pageReadinessProbe = probe
			probe.start()
		}

		private func report(
			_ reason: String,
			error: Error? = nil
		)
		{
			let failure = error as NSError?
			onDiagnostic?(Diagnostic(
				phase: phase,
				reason: reason,
				elapsed: operationStarted.duration(to: .now),
				errorDomain: failure?.domain,
				errorCode: failure?.code
			))
		}

		private func finish(_ image: Raster?)
		{
			pageReadinessProbe?.cancel()
			pageReadinessProbe = nil
			timeout?.cancel()
			timeout = nil
			operationID = nil
			let completion = continuation
			continuation = nil
			completion?.resume(returning: image)
		}

		func invalidate()
		{
			isValid = false
			webView.stopLoading()
			webView.navigationDelegate = nil
			finish(nil)
		}

		func webView(
			_ webView: WKWebView,
			didFinish navigation: WKNavigation!
		)
		{
			guard isValid, phase == "page", operationID != nil
			else
			{
				return
			}
			loaded = true
			finish(nil)
		}

		func webView(
			_ webView: WKWebView,
			didFail navigation: WKNavigation!,
			withError error: Error
		)
		{
			report(
				"navigation failed",
				error: error
			)
			invalidate()
		}

		func webView(
			_ webView: WKWebView,
			didFailProvisionalNavigation navigation: WKNavigation!,
			withError error: Error
		)
		{
			report(
				"provisional navigation failed",
				error: error
			)
			invalidate()
		}

		func webViewWebContentProcessDidTerminate(_ webView: WKWebView)
		{
			report("web content process terminated")
			invalidate()
		}

		func webView(
			_ webView: WKWebView,
			decidePolicyFor navigationAction: WKNavigationAction,
			decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
		)
		{
			decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
		}
	}
}
