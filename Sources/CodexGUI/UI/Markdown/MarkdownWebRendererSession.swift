import AppKit
import WebKit

/// Retains one offline renderer page; every admitted operation has one completion.
@MainActor
final class MarkdownWebRendererSession: NSObject, WKNavigationDelegate
{
	enum Resource: String
	{
		case mermaid = "Mermaid", math = "KaTeX"

		var entryPoint: String
		{
			self == .mermaid ? "renderMarkdownDiagram" : "renderMarkdownMath"
		}
	}
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

	struct Vector: Sendable
	{
		let svg: Data
		let pdf: Data
		let size: NSSize
		var baselineDescent: CGFloat = 0
	}

	private let resource: Resource
	private let webView: WKWebView
	private var continuation: CheckedContinuation<Vector?, Never>?
	private var timeout: Task<Void, Never>?
	private var pageReadinessProbe: MarkdownMermaidPageReadinessProbe?
	private var operationID: UUID?
	private var phase = "page"
	private var operationStarted = ContinuousClock.now
	private var onDiagnostic: (@MainActor (Diagnostic) -> Void)?
	private var pageLoadStage = 0
	private var loaded = false
	private(set) var isValid = true
	var isLoaded: Bool
	{
		loaded
	}

	init(
		resource: Resource,
		onDiagnostic: (@MainActor (Diagnostic) -> Void)? = nil
	)
	{
		self.resource = resource
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
			subdirectory: resource.rawValue
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
		maximumPixels: Int,
		typography: [String: Any],
		colors: [String: String],
		inline: Bool = false
	) async -> Vector?
	{
		guard loaded, isValid, !Task.isCancelled
		else
		{
			return nil
		}
		return await performOperation(phase: dark ? "dark vector" : "light vector")
		{
			id in
			webView.callAsyncJavaScript(
				"return await \(resource.entryPoint)(source, dark, maximumPixels,"
					+ " typography, colors, inline);",
				arguments: [
					"source": source,
					"dark": dark,
					"maximumPixels": maximumPixels,
					"typography": typography,
					"colors": colors,
					"inline": inline
				],
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
					naturalWidth <= 1_800, naturalHeight <= 1_800,
					let svg = values["svg"] as? String,
					svg.utf8.count <= min(
					1_048_576,
					maximumPixels * 4
					)
				{
					let size = NSSize(
						width: naturalWidth,
						height: naturalHeight
					)
					let configuration = WKPDFConfiguration()
					configuration.rect = NSRect(
						origin: .zero,
						size: size
					)
					configuration.allowTransparentBackground = true
					webView.createPDF(configuration: configuration)
					{
						[weak self] result in
						guard let self, operationID == id
						else
						{
							return
						}
						if case let .success(pdf) = result,
							pdf.count <= min(
							4_194_304,
							maximumPixels * 4
							),
							pdf.count + svg.utf8.count <= maximumPixels * 4
						{
							finishRender(
								Vector(
									svg: Data(svg.utf8),
									pdf: pdf,
									size: size,
									baselineDescent: values["baselineDescent"] as? Double ?? 0
								),
								operationID: id
							)
						}
						else
						{
							report("invalid vector display result")
							finishRender(
								nil,
								operationID: id
							)
						}
					}
					return
				}
				if case .success = result
				{
					report("invalid SVG result")
				}
				finishRender(
					nil,
					operationID: id
				)
			}
		}
	}

	/// Complete only after clearing the captured SVG, before another queued render can start.
	private func finishRender(
		_ vector: Vector?,
		operationID id: UUID
	)
	{
		webView.evaluateJavaScript("document.getElementById('diagram').replaceChildren();")
		{
			[weak self] _, _ in
			guard let self, operationID == id
			else
			{
				return
			}
			finish(vector)
		}
	}

	private func performOperation(
		phase: String,
		_ start: (UUID) -> Void
	) async -> Vector?
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
				pageLoadStage = 0
				armTimeout(for: id)
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

	private func armTimeout(for id: UUID)
	{
		timeout?.cancel()
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
	}

	private func advancePageLoad(to stage: Int)
	{
		guard isValid, phase == "page", let operationID, stage > pageLoadStage
		else
		{
			return
		}
		pageLoadStage = stage
		// Cold WebKit startup and native callback delivery can wait behind MainActor work.
		// Actual navigation progress starts the next bounded phase, retiring any stale
		// snapshot watchdog. Each of the two native milestones can advance only once.
		pageReadinessProbe?.cancel()
		pageReadinessProbe = nil
		armTimeout(for: operationID)
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
		// MainActor contention can deliver this timer before WebKit's navigation callbacks.
		// Accept a ready guest immediately, or allow pending native completion
		// within the probe watchdog.
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
					"({state: document.readyState, url: document.URL, "
						+ "renderer: typeof \(resource.entryPoint) === 'function'})"
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
					let state = value as? [String: Any]
					let url = (state?["url"] as? String).flatMap(URL.init(string:))
					self?.report("page probe: " + (state?["state"] as? String ?? "unknown")
						+ ", document=" + (url?.lastPathComponent ?? "unknown")
						+ ", renderer=\(state?["renderer"] as? Bool == true)")
					completion(error == nil && state?["state"] as? String == "complete"
						&& state?["renderer"] as? Bool == true)
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

	private func finish(_ image: Vector?)
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
		didStartProvisionalNavigation navigation: WKNavigation!
	)
	{
		report("navigation started")
		advancePageLoad(to: 1)
	}

	func webView(
		_ webView: WKWebView,
		didCommit navigation: WKNavigation!
	)
	{
		report("navigation committed")
		advancePageLoad(to: 2)
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
		if let pageReadinessProbe
		{
			pageReadinessProbe.confirmReadiness()
		}
		else
		{
			loaded = true
			finish(nil)
		}
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
		report("navigation policy: " +
			(navigationAction.request.url?.lastPathComponent ?? "unknown"))
		decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)
	}
}
