import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSourcesRenderingTests
{
	@Test func collapsedOperationsBuildResultsOnExpansionAndReuseThemWhenReopened() throws
	{
		_ = NSApplication.shared
		let controller = try controller(entries: [tool(
			"first",
			result: "Recorded result"
		)])
		#expect(cards(controller).isEmpty)
		let button = try disclosure(controller)
		button.performClick(nil)
		let card = try #require(cards(controller).first)
		#expect(text(in: card).contains("Recorded result"))
		button.performClick(nil)
		button.performClick(nil)
		#expect(cards(controller).count == 1)
		#expect(cards(controller).first === card)
	}

	@Test func completionReplacesOnlyChangedResultsAndRetainsTextSelection() throws
	{
		_ = NSApplication.shared
		let unchanged = try tool(
			"unchanged",
			result: "Retained result"
		)
		let started = try tool(
			"changing",
			status: "inProgress",
			result: ""
		)
		let controller = try controller(entries: [unchanged, started])
		try disclosure(controller).performClick(nil)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 220
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 600,
			height: 220
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let retained = try card(
			controller,
			invocationID: "unchanged"
		)
		let replaced = try card(
			controller,
			invocationID: "changing"
		)
		let textView = try #require(descendants(retained).compactMap
		{
			$0 as? NSTextView
		}.first)
		#expect(window.makeFirstResponder(textView))
		textView.setSelectedRange(NSRange(
			location: 0,
			length: 8
		))
		let scroll = try #require(controller.view as? NSScrollView)
		let document = scroll.documentView
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: 40
		))
		let origin = scroll.contentView.bounds.origin
		controller.update(ConversationLocalSources(entries: [
			unchanged,
			try tool(
				"changing",
				result: "Completed result"
			),
		]))
		#expect(scroll.documentView === document)
		#expect(try disclosure(controller).state == .on)
		#expect(try card(
			controller,
			invocationID: "unchanged"
		) === retained)
		#expect(textView.selectedRange() == NSRange(
			location: 0,
			length: 8
		))
		#expect(window.firstResponder === textView)
		#expect(abs(scroll.contentView.bounds.origin.y - origin.y) < 1)
		#expect(try card(
			controller,
			invocationID: "changing"
		) !== replaced)
		#expect(text(in: try card(
			controller,
			invocationID: "changing"
		))
		.contains("Completed result"))
	}

	@Test func toolUpdatesRetainLoadedMediaRowsWithoutReloadingUnavailableFiles() async throws
	{
		_ = NSApplication.shared
		let imageURL = try await imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let attachment = try imageEntry(imageURL)
		let controller = try controller(entries: [
			attachment,
			tool(
				"changing",
				status: "inProgress",
				result: ""
			),
		])
		_ = controller.view
		await controller.waitForPreviews()
		let record = try #require(controller.sources.records.first
		{
			$0.kind == .image
		})
		let image = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSImageView
		}
		.first
		{
			$0.identifier?.rawValue == "source-icon:\(record.id)"
		})
		let preview = try #require(image.image)
		let button = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue == "source-open:\(record.id)"
		})
		try FileManager.default.removeItem(at: imageURL)
		controller.update(ConversationLocalSources(entries: [
			attachment,
			try tool(
				"changing",
				result: "Completed result"
			),
		]))
		await controller.waitForPreviews()
		let views = descendants(controller.view)
		#expect(views.contains
		{
			$0 === image
		})
		#expect(views.contains
		{
			$0 === button
		})
		#expect(image.image === preview)
	}

	@Test func retainedResourceRowsKeepTheirFullWidthAfterAnUnrelatedToolUpdate() throws
	{
		_ = NSApplication.shared
		let attachment = try imageEntry(URL(fileURLWithPath: "/tmp/source-width-fixture.png"))
		let controller = try controller(entries: [
			attachment,
			tool(
				"changing",
				status: "inProgress",
				result: ""
			),
		])
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 600,
			height: 500
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let image = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSImageView
		}
		.first)
		let row = try #require(image.superview)
		let stack = try #require(row.superview as? NSStackView)
		let width = row.frame.width
		#expect(width > 400)
		controller.update(ConversationLocalSources(entries: [
			attachment,
			try tool(
				"changing",
				result: "Completed result"
			),
		]))
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		#expect(image.superview === row)
		#expect(row.superview === stack)
		#expect(abs(row.frame.width - width) < 1)
		#expect(abs(row.frame.width - stack.frame.width) < 1)
		#expect(stack.constraints.contains
		{
			$0.isActive && ($0.firstItem as? NSView) === row
				&& ($0.secondItem as? NSView) === stack
				&& $0.firstAttribute == .width && $0.secondAttribute == .width
		})
	}

	@Test func hiddenUpdatesDeferResultsAndRevealOnlyTheLatestRevision() throws
	{
		_ = NSApplication.shared
		let controller = try controller(entries: [tool(
			"changing",
			result: "Original result"
		)])
		try disclosure(controller).performClick(nil)
		let original = try card(
			controller,
			invocationID: "changing"
		)
		controller.view.isHidden = true
		controller.update(ConversationLocalSources(entries: [
			try tool(
				"changing",
				result: "Intermediate result"
			),
		]))
		controller.update(ConversationLocalSources(entries: [
			try tool(
				"changing",
				result: "Latest result"
			),
			try tool(
				"added",
				result: "Added result"
			),
		]))
		#expect(cards(controller).count == 1)
		#expect(cards(controller).first === original)
		#expect(text(in: original).contains("Original result"))
		controller.view.isHidden = false
		controller.prepareForDisplay()
		#expect(try disclosure(controller).title == "Listed pages 2 times")
		#expect(cards(controller).count == 2)
		#expect(text(in: try card(
			controller,
			invocationID: "changing"
		)).contains("Latest result"))
		#expect(!text(in: controller.view).contains("Intermediate result"))
	}

	@Test func hiddenMediaRevisionThatReturnsToItsOriginalPathRestartsCanceledLoading() async throws
	{
		_ = NSApplication.shared
		let imageURL = try await imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let original = try imageEntry(imageURL)
		let changed = try imageEntry(URL(fileURLWithPath: "/tmp/missing-replaced-source.png"))
		let controller = try controller(entries: [original])
		_ = controller.view
		controller.view.isHidden = true
		controller.update(ConversationLocalSources(entries: [changed]))
		controller.update(ConversationLocalSources(entries: [original]))
		controller.prepareForDisplay()
		let image = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSImageView
		}
		.first)
		let placeholder = image.image
		await controller.waitForPreviews()
		#expect(image.image != nil)
		#expect(image.image !== placeholder)
		controller.view.isHidden = false
	}

	@Test(.timeLimit(.minutes(1)))
	func hiddenReplacementRejectsLateResultFromCanceledPreview() async throws
	{
		_ = NSApplication.shared
		let imageURL = try await imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let original = try imageEntry(imageURL)
		let changed = try imageEntry(URL(fileURLWithPath: "/tmp/missing-replaced-source.png"))
		let loader = SourcePreviewReplacementGate()
		let controller = try controller(
			entries: [original],
			loadThumbnail:
			{
				await loader.load(path: $0)
			}
		)
		_ = controller.view
		let initial = try #require(controller.previewTasks().first)
		do
		{
			var requests = loader.requests.makeAsyncIterator()
			try #require(await requests.next() == imageURL.path)
			controller.view.isHidden = true
			controller.update(ConversationLocalSources(entries: [changed]))
			#expect(initial.isCancelled)
			#expect(controller.previewTasks().isEmpty)
			controller.update(ConversationLocalSources(entries: [original]))
			controller.prepareForDisplay()
			try #require(await requests.next() == imageURL.path)
			let image = try #require(descendants(controller.view).compactMap
			{
				$0 as? NSImageView
			}.first)
			let placeholder = image.image
			await loader.releaseNext(data: nil)
			await initial.value
			#expect(image.image === placeholder)
			#expect(!text(in: controller.view).contains("Preview unavailable"))
			await loader.releaseNext(data: try DraftImageImportTestFixture.png())
			await controller.waitForPreviews()
			#expect(image.image !== placeholder)
			controller.view.isHidden = false
			await loader.releaseAll()
		}
		catch
		{
			controller.invalidate()
			await loader.releaseAll()
			await initial.value
			throw error
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func invalidationCancelsMediaAndRejectsRetainedCallbacks() async throws
	{
		_ = NSApplication.shared
		let imageURL = try await imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let loader = SourcePreviewLoadGate(data: try DraftImageImportTestFixture.png())
		let controller = try controller(
			entries: [
				imageEntry(imageURL),
				tool(
					"first",
					result: "Recorded result"
				),
			],
			loadThumbnail:
			{
				await loader.load(path: $0)
			}
		)
		_ = controller.view
		let previews = controller.previewTasks()
		do
		{
			try #require(previews.count == 1)
			var requests = loader.requests.makeAsyncIterator()
			try #require(await requests.next() == imageURL.path)
			let views = descendants(controller.view)
			let image = try #require(views.compactMap
			{
				$0 as? NSImageView
			}.first)
			let placeholder = image.image
			let source = try #require(views.compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.identifier?.rawValue.hasPrefix("source-open:") == true
			})
			let operation = try disclosure(controller)
			var openCount = 0
			controller.onOpen =
			{
				_ in openCount += 1; return true
			}
			controller.invalidate()
			#expect(previews.allSatisfy
			{
				$0.isCancelled
			})
			#expect(controller.previewTasks().isEmpty)
			await loader.release()
			for preview in previews
			{
				await preview.value
			}
			#expect(await loader.cancelledAtReturn == [true])
			try #require(source.dispatchConfiguredAction())
			operation.state = .on
			try #require(operation.dispatchConfiguredAction())
			controller.prepareForDisplay()
			#expect(openCount == 0)
			#expect(image.image === placeholder)
			#expect(cards(controller).isEmpty)
		}
		catch
		{
			controller.invalidate()
			await loader.release()
			for preview in previews
			{
				await preview.value
			}
			throw error
		}
	}

	@Test func supportedAndUnknownRecordedContentReachesSourceCards() throws
	{
		_ = NSApplication.shared
		let cases: [([String: Any], String)] = [
			(["content": [["type": "resource", "resource": [
				"uri": "file:///guide.md",
				"text": "Embedded resource text"
			]]]], "Embedded resource text"),
			(["content": [["type": "resource_link",
							"uri": "https://example.com/guide",
							"name": "Linked resource"]]], "Linked resource"),
			(
				["content": [["type": "image", "mimeType": "image/png", "data": "AAAA"]]],
				"Recorded image data"
			),
			(
				["content": [["type": "future", "value": "Unknown recorded value"]]],
				"Unknown recorded value"
			),
			(["isError": true,
				"content": [],
				"structuredContent": ["message": "Access denied"]], "Access denied"),
		]
		for (result, expected) in cases
		{
			let item = try #require(CodexItem(json: [
				"id": "result",
				"type": "mcpToolCall",
				"status": "completed",
				"server": "chatgpt_space",
				"tool": "read_page",
				"result": result,
			]))
			let entry = ConversationContentReducer.entry(
				for: item,
				id: "turn:result"
			)
			let controller = try controller(entries: [entry])
			defer
			{
				controller.invalidate()
			}
			let button = try disclosure(controller)
			button.state = .on
			try #require(button.dispatchConfiguredAction())
			let card = try card(
				controller,
				invocationID: "result"
			)
			#expect(text(in: card).contains(expected))
			#expect(!text(in: card).contains("No result recorded"))
		}
	}

	private func controller(
		entries: [ConversationEntry],
		loadThumbnail: @escaping @Sendable (String) async -> Data? = SourceThumbnailLoader
			.load(path:)
	) throws
		-> ConversationSourcesViewController
	{
		let snapshot = WorkspaceSelectors.snapshot(
			model: WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/fixture/workspace"
			)),
			now: .distantPast
		)
		return ConversationSourcesViewController(
			owner: FeaturePresentationOwner(snapshot),
			sources: ConversationLocalSources(entries: entries),
			loadThumbnail: loadThumbnail
		)
	}

	private func tool(
		_ id: String,
		status: String = "completed",
		result: String
	) throws -> ConversationEntry
	{
		let item = try #require(CodexItem(json: [
			"id": id,
			"type": "mcpToolCall",
			"server": "chatgpt_space",
			"tool": "list_pages",
			"status": status,
			"arguments": [:],
			"result": ["text": result],
		]))
		return ConversationContentReducer.entry(
			for: item,
			id: "turn:\(id)"
		)
	}

	private func imageEntry(_ url: URL) throws -> ConversationEntry
	{
		let reference = try #require(UserMessageReference(
			json: ["type": "localImage", "path": url.path],
			id: "image"
		))
		return ConversationEntry(
			id: "turn:user",
			kind: .user,
			title: "You",
			body: "",
			imageAttachments: [reference]
		)
	}

	private func imageFile() async throws -> URL
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("sources-rendering-\(UUID()).png")
		let png = try DraftImageImportTestFixture.png()
		try await BackgroundTestWork.perform
		{
			try png.write(to: url)
		}
		return url
	}

	private func disclosure(_ controller: NSViewController) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue.hasPrefix("source-disclosure:") == true
		})
	}

	private func card(
		_ controller: NSViewController,
		invocationID: String
	) throws -> SourceResultCodeCard
	{
		try #require(cards(controller).first
		{
			$0.identifier?.rawValue.hasSuffix(":turn:\(invocationID)") == true
		})
	}

	private func cards(_ controller: NSViewController) -> [SourceResultCodeCard]
	{
		descendants(controller.view).compactMap
		{
			$0 as? SourceResultCodeCard
		}
	}

	private func text(in view: NSView) -> String
	{
		descendants(view).compactMap
		{
			($0 as? NSTextView)?.string ?? ($0 as? NSTextField)?.stringValue
		}.joined(separator: "\n")
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}

private actor SourcePreviewLoadGate
{
	nonisolated let requests: AsyncStream<String>
	private let requestContinuation: AsyncStream<String>.Continuation
	private let data: Data
	private var released = false
	private var waiters: [CheckedContinuation<Void, Never>] = []
	private(set) var cancelledAtReturn: [Bool] = []

	init(data: Data)
	{
		let (requests, continuation) = AsyncStream<String>.makeStream()
		self.requests = requests
		requestContinuation = continuation
		self.data = data
	}

	func load(path: String) async -> Data?
	{
		// Return real image data even after cancellation to exercise the view's late-result guard.
		await withCheckedContinuation
		{
			continuation in
			if released
			{
				continuation.resume()
			}
			else
			{
				waiters.append(continuation)
			}
			requestContinuation.yield(path)
		}
		cancelledAtReturn.append(Task.isCancelled)
		return data
	}

	func release()
	{
		released = true
		let pending = waiters
		waiters.removeAll()
		for waiter in pending
		{
			waiter.resume()
		}
		requestContinuation.finish()
	}
}

private actor SourcePreviewReplacementGate
{
	nonisolated let requests: AsyncStream<String>
	private let requestContinuation: AsyncStream<String>.Continuation
	private var waiters: [CheckedContinuation<Data?, Never>] = []

	init()
	{
		let (requests, continuation) = AsyncStream<String>.makeStream()
		self.requests = requests
		requestContinuation = continuation
	}

	func load(path: String) async -> Data?
	{
		await withCheckedContinuation
		{
			continuation in
			waiters.append(continuation)
			requestContinuation.yield(path)
		}
	}

	func releaseNext(data: Data?)
	{
		guard !waiters.isEmpty
		else
		{
			return
		}
		waiters.removeFirst().resume(returning: data)
	}

	func releaseAll()
	{
		let pending = waiters
		waiters.removeAll()
		for waiter in pending
		{
			waiter.resume(returning: nil)
		}
		requestContinuation.finish()
	}
}
