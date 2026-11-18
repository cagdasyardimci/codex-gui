import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationTranscriptUpdateLayoutTests
{

	@Test func streamingReusesFixedHeightRowsAndRefreshesGrownRowsWithoutMovingTheReader(
	) async throws
	{
		_ = NSApplication.shared
		let fixture = WindowFixture(
			width: 700,
			height: 760
		)
		let controller = fixture.controller
		let collection = controller.transcript.collectionView
		let scroll = controller.transcript.conversationScrollView
		defer
		{
			fixture.tearDown()
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
		controller.transcript.readingPositionChanged()
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
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "entry-20")
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
		#expect(controller.transcript.readingAnchor()?.sourceEntryID == "entry-20")
	}

	@Test func openingCommandOutputNearBottomKeepsTheHeaderInPlace() async throws
	{
		_ = NSApplication.shared
		let fixture = WindowFixture(
			width: 700,
			height: 760
		)
		defer
		{
			fixture.tearDown()
		}
		let controller = fixture.controller
		let transcript = controller.transcript
		let command = ConversationEntry(
			id: "command",
			kind: .command,
			title: "Command",
			body: "",
			activity: .command(ConversationCommand(
				command: "printf 'output'",
				cwd: nil,
				output: String(
					repeating: "output\n",
					count: 100
				),
				status: "completed",
				exitCode: 0,
				durationMs: nil,
				actions: []
			))
		)
		controller.render(snapshot(historyEntries(0 ..< 40) + [command]))
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		transcript.collectionView.layoutSubtreeIfNeeded()
		let clip = transcript.conversationScrollView.contentView
		let index = try #require(transcript.displayedRows.firstIndex
		{
			$0.id == command.id
		})
		let path = IndexPath(
			item: index,
			section: 0
		)
		guard case .activity(let row) = transcript.displayedRows[index]
		else
		{
			Issue.record("Expected a command row")
			return
		}
		let before = try #require(transcript.collectionView.layoutAttributesForItem(at: path)).frame
		try #require(transcript.isNearBottom)
		try #require(before.intersects(clip.bounds))
		let headerOffset = before.minY - clip.bounds.minY

		transcript.toggleActivity(row)
		await controller.waitForRendering()

		let after = try #require(transcript.collectionView.layoutAttributesForItem(at: path)).frame
		#expect(after.height > before.height)
		#expect(abs(after.minY - clip.bounds.minY - headerOffset) < 1)
	}

	@Test func liveScrollingToTopLoadsOnePageAndRespectsLoadingAndHistoryAvailability() async throws
	{
		_ = NSApplication.shared
		let fixture = WindowFixture(
			width: 700,
			height: 760
		)
		defer
		{
			fixture.tearDown()
		}
		let controller = fixture.controller
		let transcript = controller.transcript
		let scroll = transcript.conversationScrollView
		let entries = historyEntries(0 ..< 30)
		var requests = 0
		transcript.onLoadEarlierTurns =
		{
			requests += 1
		}
		controller.render(snapshot(
			entries,
			canLoadEarlierTurns: true
		))
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		#expect(requests == 0)

		func liveScroll(to y: CGFloat)
		{
			scroll.contentView.scroll(to: NSPoint(
				x: 0,
				y: y
			))
			scroll.reflectScrolledClipView(scroll.contentView)
			NotificationCenter.default.post(
				name: NSScrollView.didLiveScrollNotification,
				object: scroll
			)
		}
		liveScroll(to: 100)
		#expect(requests == 0)
		// A layout-driven bounds notification at the top must not fetch history.
		scroll.contentView.scroll(to: .zero)
		transcript.readingPositionChanged()
		#expect(requests == 0)
		liveScroll(to: 0)
		liveScroll(to: 0)
		#expect(requests == 1)

		controller.render(snapshot(
			entries,
			canLoadEarlierTurns: false
		))
		liveScroll(to: 0)
		#expect(requests == 1)
		controller.render(snapshot(
			entries,
			canLoadEarlierTurns: true
		))
		transcript.setLoadEarlierEnabled(false)
		liveScroll(to: 0)
		#expect(requests == 1)
		transcript.setLoadEarlierEnabled(true)
		liveScroll(to: 0)
		#expect(requests == 2)

		controller.render(snapshot(
			historyEntries(-10 ..< 30),
			canLoadEarlierTurns: true
		))
		await controller.waitForRendering()
		#expect(requests == 2)
		liveScroll(to: 0)
		#expect(requests == 3)
		controller.render(snapshot(
			entries,
			canLoadEarlierTurns: true,
			threadID: "another-chat"
		))
		await controller.waitForRendering()
		#expect(requests == 3)
		liveScroll(to: 0)
		#expect(requests == 4)
		// A fast failure can finish before a loading snapshot is published.
		NotificationCenter.default.post(
			name: NSScrollView.didEndLiveScrollNotification,
			object: scroll
		)
		liveScroll(to: 0)
		#expect(requests == 5)
		controller.render(snapshot(
			historyEntries(0 ..< 1),
			canLoadEarlierTurns: true,
			threadID: "short-chat"
		))
		await controller.waitForRendering()
		#expect(requests == 5)
		// Short content may not move, but starting a scroll at its top still loads history.
		NotificationCenter.default.post(
			name: NSScrollView.willStartLiveScrollNotification,
			object: scroll
		)
		#expect(requests == 6)
	}

	@Test(arguments: [1, 30])
	func prependingHistoryPreservesTheTopMessageAndOffset(existingCount: Int) async throws
	{
		_ = NSApplication.shared
		let fixture = WindowFixture(
			width: 700,
			height: 760
		)
		defer
		{
			fixture.tearDown()
		}
		let controller = fixture.controller
		let transcript = controller.transcript
		controller.render(snapshot(
			historyEntries(0 ..< existingCount),
			canLoadEarlierTurns: true
		))
		await controller.waitForRendering()
		controller.view.layoutSubtreeIfNeeded()
		let clip = transcript.conversationScrollView.contentView
		clip.scroll(to: .zero)
		let before = try #require(transcript.readingAnchor())
		controller.render(snapshot(
			historyEntries(-40 ..< existingCount),
			canLoadEarlierTurns: true
		))
		await controller.waitForRendering()
		let index = try #require(transcript.displayedRows.firstIndex
		{
			$0.id == before.entryID
		})
		let frame = try #require(transcript.collectionView.layoutAttributesForItem(
			at: IndexPath(
				item: index,
				section: 0
			)
		)).frame
		let maximumY = max(
			0,
			transcript.collectionView.bounds.height - clip.bounds.height
		)
		let expectedY = min(
			maximumY,
			max(
				0,
				frame.minY + before.offset
			)
		)
		#expect(abs(clip.bounds.minY - expectedY) < 1)
		#expect(frame.intersects(clip.bounds))
	}

	private func historyEntries(_ indices: Range<Int>) -> [ConversationEntry]
	{
		indices.map
		{
			ConversationEntry(
				id: "entry-\($0)",
				kind: .agent,
				title: "Codex",
				body: "Message \($0)"
			)
		}
	}

	@MainActor
	private struct WindowFixture
	{
		let controller: ConversationViewController
		let window: NSWindow

		init(
			width: CGFloat,
			height: CGFloat
		)
		{
			controller = ConversationViewController()
			window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: width,
					height: height
				),
				styleMask: [.titled, .resizable],
				backing: .buffered,
				defer: false
			)
			window.contentViewController = controller
			window.setContentSize(NSSize(
				width: width,
				height: height
			))
		}

		func tearDown()
		{
			controller.transcript.cancelWidthChangeReadingPosition()
			controller.transcript.collectionView.dataSource = nil
			controller.transcript.collectionView.delegate = nil
			window.contentViewController = nil
			window.prepareForTesting()
			window.close()
		}
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
			return controller.transcript.collectionView(
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
		canLoadEarlierTurns: Bool = false,
		threadID: String = "reading"
	) -> ConversationSnapshot
	{
		ConversationSnapshot(
			projectPath: "/tmp/layout-streaming",
			threads: [],
			selectedThreadID: threadID,
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
