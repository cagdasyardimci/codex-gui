import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationSourceTypesRenderingTests
{
	@Test func typedResourcesUseDistinctIconsAndPreserveTheirOriginLabels() throws
	{
		_ = NSApplication.shared
		let sources = ConversationLocalSources(entries: [try entry(
			[
				"id": "user",
				"type": "userMessage",
				"content": [
					[
						"type": "mention",
						"name": "Implementation",
						"path": "/tmp/source-types/implementation.swift"
					],
					[
						"type": "mention",
						"name": "Recorded discussion",
						"path": "/tmp/source-types/discussion.mp3"
					],
					[
						"type": "mention",
						"name": "Specification",
						"path": "/tmp/source-types/specification.pdf"
					],
					[
						"type": "mention",
						"name": "Reference folder",
						"path": "/tmp/source-types/reference-folder/"
					],
					["type": "localImage", "path": "/tmp/source-types/diagram.png"],
				]
			],
			scope: "turn:user"
		)])
		let controller = ConversationSourcesViewController(
			owner: owner(),
			sources: sources
		)
		let views = descendants(controller.view)
		let expectedIcons: [(ConversationLocalSources.Kind, DesktopIcon, CGFloat)] = [
			(.file, .file, 24),
			(.audio, .fileAudio, 18),
			(.pdf, .fileDocument, 24),
			(.folder, .folder, 24),
			(.image, .fileImage, 24),
		]
		try #require(sources.records.count == expectedIcons.count)
		var renderedIcons = Set<Data>()
		for (record, expected) in zip(
			sources.records,
			expectedIcons
		)
		{
			#expect(record.kind == expected.0)
			#expect(record.iconIdentifier == expected.1)
			let icon = try #require(views.compactMap
			{
				$0 as? NSImageView
			}.first
			{
				$0.identifier?.rawValue == "source-icon:\(record.id)"
			})
			let image = try #require(icon.image)
			#expect(image.size == NSSize(
				width: expected.2,
				height: expected.2
			))
			let pixels = try iconPixels(image)
			let expectedPixels = try iconPixels(DesktopIcons.image(
				expected.1,
				size: expected.2
			))
			#expect(pixels == expectedPixels)
			renderedIcons.insert(pixels)
			#expect(icon.toolTip == record.kind.rawValue)
			let button = try #require(views.compactMap
			{
				$0 as? NSButton
			}.first
			{
				$0.identifier?.rawValue == "source-open:\(record.id)"
			})
			#expect(button.title == record.name)
			#expect(button.accessibilityLabel() == "Open source: \(record.name)")
		}
		#expect(renderedIcons.count == expectedIcons.count)
		let labels = views.compactMap
		{
			$0 as? NSTextField
		}.map(\.stringValue)
		#expect(labels.filter
		{
			$0 == "Attached to the conversation"
		}.count == 5)
		#expect(labels.filter
		{
			$0 == "Image unavailable"
		}.count == 1)
		#expect(labels.filter
		{
			$0 == "Source unavailable"
		}.count == 4)
		try captureIfRequested(controller)
	}

	@Test func explicitReadPageMetadataCreatesPageProvenanceWithoutInventingMissingMetadata() throws
	{
		let entry = try self.entry(
			[
				"id": "read",
				"type": "mcpToolCall",
				"server": "chatgpt_space",
				"tool": "read_page",
				"status": "completed",
				"arguments": ["page_id": "page-123"],
				"result": ["structuredContent": [
					"page_id": "page-123",
					"title": "Research notes",
					"url": "https://chatgpt.com/pages/page-123"
				]],
			],
			scope: "turn:read"
		)
		let sources = ConversationLocalSources(entries: [entry])
		let page = try #require(sources.records.first
		{
			$0.kind == .page
		})
		#expect(page.name == "Research notes")
		#expect(page.path == "https://chatgpt.com/pages/page-123")
		#expect(page.association == "Read during the chat")
		#expect(page.url?.absoluteString == page.path)
		let unknown = try self.entry(
			[
				"id": "read",
				"type": "mcpToolCall",
				"server": "chatgpt_space",
				"tool": "read_page",
				"status": "completed",
				"arguments": ["page_id": "page-unknown"],
				"result": ["content": [[
					"type": "text",
					"text": "Read Research notes in the Space."
				]]],
			],
			scope: "turn:unknown"
		)
		#expect(!ConversationLocalSources(entries: [unknown]).records.contains
		{
			$0.kind == .page
		})
		let controller = ConversationSourcesViewController(
			owner: owner(),
			sources: sources
		)
		let labels = descendants(controller.view).compactMap
		{
			$0 as? NSTextField
		}
		.map(\.stringValue)
		#expect(labels.contains("Read during the chat"))
		#expect(labels.contains(page.path))
	}

	@Test func activityRowsShowOperationCountsAndKeepDisclosureOpenAfterCompletion() throws
	{
		_ = NSApplication.shared
		let started = try entry(
			[
				"id": "tool",
				"type": "mcpToolCall",
				"server": "chatgpt_space",
				"tool": "list_pages",
				"status": "inProgress",
			],
			scope: "turn:tool"
		)
		let completed = try entry(
			[
				"id": "tool",
				"type": "mcpToolCall",
				"server": "chatgpt_space",
				"tool": "list_pages",
				"status": "completed",
				"result": ["text": "Research pages ready"],
			],
			scope: "turn:tool"
		)
		let otherEntries = [
			try entry(
				["id": "search", "type": "webSearch", "action": [
					"type": "search",
					"query": "first query"
				]],
				scope: "turn-one:search"
			),
			try entry(
				["id": "search", "type": "webSearch", "action": [
					"type": "search",
					"query": "second query"
				]],
				scope: "turn-two:search"
			),
			try entry(
				["id": "open", "type": "webSearch", "action": [
					"type": "openPage",
					"url": "https://example.com"
				]],
				scope: "turn:open"
			),
			try entry(
				["id": "find", "type": "webSearch", "action": [
					"type": "findInPage",
					"url": "https://example.com",
					"pattern": "reference"
				]],
				scope: "turn:find"
			),
			try tool(
				"list_threads",
				server: "codex_app",
				scope: "turn:app"
			),
		]
		let sources = ConversationLocalSources(entries: [started] + otherEntries)
		let controller = ConversationSourcesViewController(
			owner: owner(),
			sources: sources
		)
		let views = descendants(controller.view)
		let titles = views.compactMap
		{
			$0 as? NSButton
		}.map(\.title)
		#expect(titles.contains("Listed pages once"))
		#expect(titles.contains("Searched 2 times"))
		#expect(titles.contains("Opened 1 page"))
		#expect(titles.contains("Found text on 1 page"))
		for record in sources.records
		{
			let icon = try #require(views.compactMap
			{
				$0 as? NSImageView
			}.first
			{
				$0.identifier?.rawValue == "source-icon:\(record.id)"
			})
			#expect(icon.image != nil)
		}
		try captureIfRequested(
			controller,
			name: "sources-activity-types"
		)
		let space = try #require(sources.records.first
		{
			$0.name == "Space"
		})
		let disclosureID = "source-disclosure:\(space.id):operation:list_pages"
		let disclosure = try #require(views.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue == disclosureID
		})
		disclosure.performClick(nil)
		#expect(disclosure.state == .on)
		controller.update(ConversationLocalSources(entries: [completed] + otherEntries))
		let updatedViews = descendants(controller.view)
		let updatedDisclosure = try #require(updatedViews.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.identifier?.rawValue == disclosureID
		})
		#expect(updatedDisclosure.state == .on)
		#expect(updatedDisclosure.title == "Listed pages once")
		let detail = try #require(updatedViews.first
		{
			$0.identifier?.rawValue == "source-detail:\(space.id):operation:list_pages"
		})
		#expect(!detail.isHidden)
		let result = try #require(descendants(detail).compactMap
		{
			$0 as? NSTextView
		}.first)
		#expect(result.string.contains("Research pages ready"))
		#expect(!result.string.contains("completed"))
	}

	private func entry(
		_ json: [String: Any],
		scope: String
	) throws -> ConversationEntry
	{
		ConversationContentReducer.entry(
			for: try #require(CodexItem(json: json)),
			id: scope
		)
	}

	private func tool(
		_ operation: String,
		server: String,
		scope: String
	) throws -> ConversationEntry
	{
		try entry(
			[
				"id": "reused-tool",
				"type": "mcpToolCall",
				"server": server,
				"tool": operation,
				"status": "completed",
				"arguments": [:],
				"result": ["text": "Recorded result"],
			],
			scope: scope
		)
	}

	private func owner() -> FeaturePresentationOwner
	{
		let model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/fixture/workspace"
		))
		return FeaturePresentationOwner(WorkspaceSelectors.snapshot(
			model: model,
			now: .distantPast
		))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private func iconPixels(_ image: NSImage) throws -> Data
	{
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil,
			pixelsWide: 48,
			pixelsHigh: 48,
			bitsPerSample: 8,
			samplesPerPixel: 4,
			hasAlpha: true,
			isPlanar: false,
			colorSpaceName: .deviceRGB,
			bytesPerRow: 192,
			bitsPerPixel: 32
		))
		let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSGraphicsContext.current = context
		let bounds = NSRect(
			x: 0,
			y: 0,
			width: 48,
			height: 48
		)
		context.cgContext.clear(bounds)
		image.draw(in: bounds)
		let bytes = try #require(bitmap.bitmapData)
		let pixels = Data(
			bytes: bytes,
			count: bitmap.bytesPerRow * bitmap.pixelsHigh
		)
		#expect(pixels.contains
		{
			$0 != 0
		})
		return pixels
	}

	private func captureIfRequested(
		_ controller: NSViewController,
		name: String = "sources-mixed-types"
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_SOURCES_QA_DIR"]
		else
		{
			return
		}
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 800,
				height: 800
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 800,
			height: 800
		))
		defer
		{
			window.close()
		}
		window.layoutIfNeeded()
		controller.view.layoutSubtreeIfNeeded()
		let destination = URL(
			fileURLWithPath: directory,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: destination,
			withIntermediateDirectories: true
		)
		let bitmap = try #require(controller.view
			.bitmapImageRepForCachingDisplay(in: controller.view.bounds))
		controller.view.cacheDisplay(
			in: controller.view.bounds,
			to: bitmap
		)
		let data = try #require(bitmap.representation(
			using: .png,
			properties: [:]
		))
		try data.write(to: destination.appendingPathComponent(name + ".png"))
	}
}
