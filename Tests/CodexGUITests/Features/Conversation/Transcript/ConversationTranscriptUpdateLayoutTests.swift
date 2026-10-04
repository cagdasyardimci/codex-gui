import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTranscriptUpdateLayoutTests
{
	@Test(arguments: [false, true])
	func scrollingToEndKeepsTranscriptRowsInTheViewport(canLoadEarlierTurns: Bool) async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 900,
			height: 760
		))
		defer
		{
			controller.cancelWidthChangeReadingPosition()
			controller.collectionView.dataSource = nil
			controller.collectionView.delegate = nil
			window.contentViewController = nil
			window.isReleasedWhenClosed = false
			window.close()
		}
		let entries = (0 ..< 160).map
		{
			index in
			if index % 4 != 0
			{
				return ConversationEntry(
					id: "turn:command-\(index)",
					kind: .command,
					title: "Command",
					body: "",
					activity: .command(ConversationCommand(
						command: "git status",
						cwd: nil,
						output: "Complete",
						status: "completed",
						exitCode: 0,
						durationMs: 1,
						actions: []
					))
				)
			}
			return ConversationEntry(
				id: "turn:entry-\(index)",
				kind: .agent,
				title: "Codex",
				body: "Message \(index)\n\n" + String(
					repeating: "Transcript text. ",
					count: 40
				)
			)
		}
		controller.render(snapshot(
			Array(entries.prefix(100)),
			canLoadEarlierTurns: canLoadEarlierTurns
		))
		await controller.waitForRendering()
		for end in [120, 140, 160]
		{
			controller.render(snapshot(
				Array(entries.prefix(end)),
				canLoadEarlierTurns: canLoadEarlierTurns
			))
			await controller.waitForRendering()
		}
		let collection = controller.collectionView
		let scroll = controller.conversationScrollView
		let layout = try #require(collection.collectionViewLayout)
		for fraction in [CGFloat(0), 0.5, 1, 0.25, 1]
		{
			controller.view.layoutSubtreeIfNeeded()
			let bottom = layout.collectionViewContentSize.height - scroll.contentSize.height
			scroll.contentView.scroll(to: NSPoint(
				x: 0,
				y: bottom * fraction
			))
			scroll.reflectScrolledClipView(scroll.contentView)
			collection.layoutSubtreeIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			#expect(scroll.frame.height > window.contentLayoutRect.height / 2)
			#expect(controller.latestButton.isHidden == (fraction == 1))
			let visible = layout.layoutAttributesForElements(in: collection.visibleRect)
			#expect(!visible.isEmpty)
			for attributes in visible
			{
				let path = try #require(attributes.indexPath)
				let item = try #require(collection.item(at: path))
				#expect(item.view.frame == attributes.frame)
			}
			#expect(abs(collection.frame.height - layout.collectionViewContentSize.height) < 1)
		}
	}

	@Test func streamingReusesFixedHeightRowsAndRefreshesGrownRowsWithoutMovingTheReader(
	) async throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 700,
				height: 760
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = controller
		window.setContentSize(NSSize(
			width: 700,
			height: 760
		))
		let collection = controller.collectionView
		let scroll = controller.conversationScrollView
		defer
		{
			controller.cancelWidthChangeReadingPosition()
			collection.dataSource = nil
			collection.delegate = nil
			window.contentViewController = nil
			window.isReleasedWhenClosed = false
			window.close()
		}
		var entries = (0 ..< 80).map
		{
			ConversationEntry(
				id: "entry-\($0)",
				kind: .agent,
				title: "Codex",
				body: "## Message \($0)\n\n" + String(
					repeating: "Earlier text. ",
					count: 20
				)
			)
		}
		entries[20].body = "alpha"
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		collection.layoutSubtreeIfNeeded()
		let layout = try #require(collection.collectionViewLayout as? ConversationFlowLayout)
		let path = IndexPath(
			item: 20,
			section: 0
		)
		let previous = try #require(layout.layoutAttributesForItem(at: path)).frame
		scroll.contentView.scroll(to: NSPoint(
			x: 0,
			y: previous.minY + 4
		))
		scroll.reflectScrolledClipView(scroll.contentView)
		controller.readingPositionChanged()
		collection.layoutSubtreeIfNeeded()
		let item = try #require(collection.item(at: path))
		let initialReaderOffset = previous.minY - scroll.contentView.bounds.minY
		let metrics = MetricRequests(controller: controller)
		collection.delegate = metrics
		entries[20].body = "omega"
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		#expect(metrics.paths.isEmpty)
		#expect(collection.item(at: path) === item)
		#expect(layout.layoutAttributesForItem(at: path)?.frame == previous)
		let text = try #require(textViews(in: item.view).first)
		#expect(text.string == "omega")
		#expect(controller.readingAnchor()?.sourceEntryID == "entry-20")
		let earlierPath = IndexPath(
			item: 0,
			section: 0
		)
		let oldHeight = try #require(layout.layoutAttributesForItem(at: earlierPath)).frame.height
		entries[0].body += String(
			repeating: " Earlier streamed text grew. ",
			count: 180
		)
		controller.render(snapshot(entries))
		await controller.waitForRendering()
		let grown = try #require(layout.layoutAttributesForItem(at: earlierPath)).frame
		#expect(grown.height > oldHeight)
		#expect(metrics.paths.contains(earlierPath))
		let following = try #require(layout.layoutAttributesForItem(at: IndexPath(
			item: 1,
			section: 0
		))).frame
		#expect(following.minY >= grown.maxY)
		let current = try #require(layout.layoutAttributesForItem(at: path)).frame
		#expect(abs(current.minY - scroll.contentView.bounds.minY - initialReaderOffset) < 1)
		#expect(controller.readingAnchor()?.sourceEntryID == "entry-20")
	}

	private final class MetricRequests: NSObject, NSCollectionViewDelegateFlowLayout
	{
		let controller: ConversationViewController
		var paths: [IndexPath] = []
		init(controller: ConversationViewController)
		{
			self.controller = controller
		}

		func collectionView(
			_ collectionView: NSCollectionView,
			layout collectionViewLayout: NSCollectionViewLayout,
			sizeForItemAt indexPath: IndexPath
		) -> NSSize
		{
			paths.append(indexPath)
			return controller.collectionView(
				collectionView,
				layout: collectionViewLayout,
				sizeForItemAt: indexPath
			)
		}
	}

	private func textViews(in view: NSView) -> [NSTextView]
	{
		if let text = view as? NSTextView
		{
			return [text]
		}
		return view.subviews.flatMap
		{
			textViews(in: $0)
		}
	}

	private func snapshot(
		_ entries: [ConversationEntry],
		canLoadEarlierTurns: Bool = false
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/layout-streaming",
			threads: [],
			selectedThreadID: "reading",
			entries: entries,
			canLoadEarlierTurns: canLoadEarlierTurns,
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
	}
}
