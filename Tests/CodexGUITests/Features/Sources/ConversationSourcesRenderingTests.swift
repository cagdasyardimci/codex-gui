import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSourcesRenderingTests
{

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
			(["isError": true,
				"structuredContent": [
				"message": NSNull(),
				"text": "Error after empty message"
				]], "Error after empty message"),
			(["isError": true,
				"structuredContent": [
				"message": false,
				"text": "Secondary error"
				]], "false"),
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

	@Test func sourceOpenActionRemainsAvailableWithoutFailureStatusFeedback() async throws
	{
		_ = NSApplication.shared
		let imageURL = try await imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let controller = try controller(entries: [imageEntry(imageURL)])
		defer
		{
			controller.invalidate()
		}
		_ = controller.view
		let source = try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue.hasPrefix("source-open:") == true
		})
		let record = try #require(controller.sources.records.first)
		var opened: String?
		controller.onOpen =
		{
			opened = $0.id
			return false
		}
		#expect(source.isEnabled)
		try #require(source.dispatchConfiguredAction())
		#expect(opened == record.id)
		#expect(descendants(controller.view).compactMap
		{
			$0 as? DesktopStatusView
		}.isEmpty)
		controller.invalidate()
		await controller.waitForPreviews()
	}

	@Test func rawOutputAndResultCardsInvalidateOnUnicodeByteReplacement() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			for includesUnrelatedUpdate in [false, true]
			{
				let original = try tool(
					"first",
					result: "é"
				)
				let replacement = try tool(
					"first",
					result: "e\u{301}"
				)
				var initial = [original]
				var updated = [replacement]
				if includesUnrelatedUpdate
				{
					initial.append(try tool(
						"second",
						status: "inProgress",
						result: ""
					))
					updated.append(try tool(
						"second",
						result: "Unrelated completion"
					))
				}
				let controller = try controller(entries: initial)
				let window = sourceWindow(controller)
				defer
				{
					controller.invalidate()
					window.close()
				}
				let button = try disclosure(controller)
				button.state = .on
				try #require(button.dispatchConfiguredAction())
				let oldCard = try card(
					controller,
					invocationID: "first"
				)
				try #require(rawButton(
					controller,
					invocationID: "first"
				)
				.dispatchConfiguredAction())
				let sheet = try #require(window.attachedSheet)
				try #require(sheet.isVisible)
				let next = ConversationLocalSources(entries: updated)
				let before = try #require(controller.sources.records.flatMap(\.invocations).first)
				let after = try #require(next.records.flatMap(\.invocations).first)
				#expect(before.detail == after.detail)
				#expect(!before.detail.utf8.elementsEqual(after.detail.utf8))
				#expect(before.resultText == after.resultText)
				#expect(!before.resultText.utf8.elementsEqual(after.resultText.utf8))
				#expect(before != after)
				#expect(controller.sources.records != next.records)
				controller.view.isHidden = includesUnrelatedUpdate
				controller.update(next)
				#expect(!sheet.isVisible)
				#expect(controller.sources.records == next.records)
				controller.view.isHidden = false
				controller.prepareForDisplay()
				let newCard = try card(
					controller,
					invocationID: "first"
				)
				#expect(newCard !== oldCard)
				let textViews = descendants(newCard).compactMap
				{
					$0 as? NSTextView
				}
				let recorded = try #require(textViews.first)
				#expect(recorded.string.utf8.elementsEqual("e\u{301}".utf8))
			}
		}
	}

	private func sourceWindow(_ controller: NSViewController) -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: -2_000,
				y: -2_000,
				width: 700,
				height: 650
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentViewController = controller
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		window.orderFront(nil)
		return window
	}

	private func rawButton(
		_ controller: NSViewController,
		invocationID: String
	) throws -> NSButton
	{
		try #require(descendants(controller.view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue == "source-show-raw:turn:\(invocationID)"
		})
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
