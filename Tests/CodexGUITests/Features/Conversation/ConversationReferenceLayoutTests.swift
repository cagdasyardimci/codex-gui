import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationReferenceLayoutTests
{
	@Test func completedTurnsKeepTheReferenceColumnAndTurnSpacing() async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 888,
				height: 1000
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.appearance = NSAppearance(named: .aqua)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 888,
			height: 1000
		))
		controller.view.layoutSubtreeIfNeeded()
		defer
		{
			window.orderOut(nil)
		}
		let image = try #require(UserMessageReference(
			json: ["type": "localImage", "path": "/tmp/reference-missing-image.png"],
			id: "reference-image"
		))
		let entries = [
			ConversationEntry(
				id: "first:user",
				kind: .user,
				title: "You",
				body: "Make such groups collapsed by default when opening a conversation in "
					+ "codex gui",
				imageAttachments: [image, image]
			),
			ConversationEntry(
				id: "first:reply",
				kind: .agent,
				title: "Codex",
				body: "Implemented: these activity groups now open collapsed, "
					+ "matching your second screenshot. "
					+ "Clicking expands them; jumping to a hidden command "
					+ "also reveals its group.\n\n"
					+ "Build, 10 focused tests, and formatting checks passed. "
					+ "Live visual verification wasn’t performed."
			),
			ConversationEntry(
				id: "second:user",
				kind: .user,
				title: "You",
				body: "First screenshot is from codex gui. Make this part collapsible "
					+ "and collapsed by default. Also there are more spaces in codex gui "
					+ "at the top and bottom of the collapsed tool use groups, "
					+ "match these spaces",
				imageAttachments: [image, image]
			),
			ConversationEntry(
				id: "second:reply",
				kind: .agent,
				title: "Codex",
				body: "Implemented:\n\n"
					+ "- “Worked for...” now collapses earlier commentary and tools by default, "
					+ "keeping the final reply visible.\n"
					+ "- Reduced spacing above and below collapsed tool groups from 18 to 8 points "
					+ "to match the reference.\n\n"
					+ "Build, 19 focused tests, and formatting checks passed. "
					+ "Live visual comparison remains unverified."
			),
		]
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/reference",
			threads: [],
			selectedThreadID: "reference",
			entries: entries,
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.turnTimings = [
			ConversationTurnTiming(
				turnID: "first",
				status: "completed",
				durationMs: 184000
			),
			ConversationTurnTiming(
				turnID: "second",
				status: "completed",
				durationMs: 310000
			),
		]
		controller.render(snapshot)
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		let collection = controller.collectionView
		collection.layoutSubtreeIfNeeded()
		let frames = try controller.displayedRows.indices.map
		{
			try #require(collection.layoutAttributesForItem(at: IndexPath(
				item: $0,
				section: 0
			)))
			.frame
		}
		#expect(controller.displayedRows.map(\.id) == [
			"first:user",
			"timing:first",
			"first:reply",
			"second:user",
			"timing:second",
			"second:reply",
		])
		try #require(frames.count == 6)
		let column = controller.view.convert(
			frames[0],
			from: collection
		)
		#expect(abs(column.minX - 76) < 0.5)
		#expect(abs(column.maxX - 812) < 0.5)
		for index in [1, 4]
		{
			#expect(abs(frames[index].minY - frames[index - 1].maxY - 50) < 0.5)
			#expect(abs(frames[index + 1].minY - frames[index].maxY - 14) < 0.5)
		}
		#expect(abs(frames[3].minY - frames[2].maxY - 40) < 0.5)
		for index in [0, 3]
		{
			let item = try #require(collection.item(at: IndexPath(
				item: index,
				section: 0
			)))
			let surface = try #require(descendants(item.view).first
			{
				$0 is DesktopSurface && !$0.isHidden
			})
			let bubble = item.view.convert(
				surface.bounds,
				from: surface
			)
			#expect(abs(bubble.width - 515.2) < 0.5)
			#expect(abs(bubble.maxX - frames[index].width) < 0.5)
		}
		if let directory = ProcessInfo.processInfo.environment["CODEX_GUI_REFERENCE_RENDER_DIR"]
		{
			collection.backgroundColors = [.white]
			for strip in descendants(controller.view)
				.compactMap(
					{
						$0 as? UserMessageImageAttachmentsView
					}
				)
			{
				await strip.waitForImages()
			}
			let rect = NSRect(
				x: 0,
				y: 0,
				width: collection.bounds.width,
				height: try #require(frames.last).maxY + 20
			)
			let bitmap = try #require(collection.bitmapImageRepForCachingDisplay(in: rect))
			collection.cacheDisplay(
				in: rect,
				to: bitmap
			)
			let context = try #require(CGContext(
				data: nil,
				width: bitmap.pixelsWide,
				height: bitmap.pixelsHigh,
				bitsPerComponent: 8,
				bytesPerRow: 0,
				space: CGColorSpaceCreateDeviceRGB(),
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			))
			let pixels = CGRect(
				x: 0,
				y: 0,
				width: bitmap.pixelsWide,
				height: bitmap.pixelsHigh
			)
			context.setFillColor(CGColor(
				gray: 1,
				alpha: 1
			))
			context.fill(pixels)
			context.draw(
				try #require(bitmap.cgImage),
				in: pixels
			)
			let preview = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
			let png = try #require(preview.representation(
				using: .png,
				properties: [:]
			))
			let url = URL(
				fileURLWithPath: directory,
				isDirectory: true
			)
			try FileManager.default.createDirectory(
				at: url,
				withIntermediateDirectories: true
			)
			try png.write(to: url.appendingPathComponent("conversation-reference.png"))
			print("Reference layout frames: \(frames)")
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
