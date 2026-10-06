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
		let imageURL = try imageFile()
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
		let imageURL = try imageFile()
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

	@Test func invalidationCancelsMediaAndRejectsRetainedCallbacks() async throws
	{
		_ = NSApplication.shared
		let imageURL = try imageFile()
		defer
		{
			try? FileManager.default.removeItem(at: imageURL)
		}
		let controller = try controller(entries: [
			imageEntry(imageURL),
			tool(
				"first",
				result: "Recorded result"
			),
		])
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
		await controller.waitForPreviews()
		source.performClick(nil)
		operation.performClick(nil)
		controller.prepareForDisplay()
		#expect(openCount == 0)
		#expect(image.image === placeholder)
		#expect(cards(controller).isEmpty)
	}

	private func controller(entries: [ConversationEntry]) throws
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
			sources: ConversationLocalSources(entries: entries)
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

	private func imageFile() throws -> URL
	{
		let url = FileManager.default.temporaryDirectory
			.appendingPathComponent("sources-rendering-\(UUID()).png")
		try DraftImageImportTestFixture.png().write(to: url)
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
