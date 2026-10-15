import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationRailInputTests
{
	@Test(arguments: [520, 700, 837])
	func referenceRailShowsTurnsFourThroughSixtyFiveWithTwentyFiveTurnsLoaded(
		height: Int
	) async throws
	{
		let fixture = try await makeFixture(
			turnCount: 25,
			height: CGFloat(height),
			startIndex: 41,
			referenceCount: 66
		)
		defer
		{
			tearDown(fixture)
		}
		let rail = fixture.controller.turnNavigationRail
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let document = try #require(scroll.documentView)
		#expect(scroll.frame.height == min(
			620,
			rail.bounds.height
		))
		#expect(rail.convert(
			scroll.frame,
			to: fixture.controller.view
		).midY
			== fixture.controller.view.bounds.midY)
		let visibleEntries = document.subviews.compactMap
		{
			view -> String? in
			guard let mark = view as? TurnNavigationMark,
					scroll.contentView.bounds.contains(mark.frame)
			else
			{
				return nil
			}
			return mark.entryID.components(separatedBy: ":").first
		}
		#expect(visibleEntries == (4 ... 65).map
		{
			"turn-\($0)"
		})
	}

	@Test(arguments: [24, 66])
	func wheelOverAVisibleMarkBelongsToTheRail(turnCount: Int) async throws
	{
		let fixture = try await makeFixture(turnCount: turnCount)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let document = try #require(scroll.documentView)
		let mark = try #require(document.subviews.last as? TurnNavigationMark)
		let point = mark.convert(
			NSPoint(
				x: 8,
				y: mark.bounds.midY
			),
			to: controller.view.superview
		)
		let target = try #require(controller.view.hitTest(point))
		#expect(target === mark)
		let transcriptOrigin = controller.conversationScrollView.contentView.bounds.origin
		let railOrigin = scroll.contentView.bounds.origin
		#expect(controller.collectionView.bounds.height
			> controller.conversationScrollView.contentView.bounds.height)
		fixture.window.sendEvent(try wheelEvent(
			30,
			window: fixture.window,
			point: target.convert(
				NSPoint(
					x: 8,
					y: target.bounds.midY
				),
				to: nil
			)
		))
		// DesktopWindow routes this wheel event synchronously to the rail scroll view.
		#expect(controller.conversationScrollView.contentView.bounds.origin == transcriptOrigin)
		if turnCount > 62
		{
			#expect(scroll.contentView.bounds.origin != railOrigin)
		}
		else
		{
			#expect(scroll.contentView.bounds.origin == railOrigin)
		}
	}

	@Test func wheelOverTheRailGutterScrollsOnlyItsMarks() async throws
	{
		let fixture = try await makeFixture(turnCount: 66)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let gutterPoint = NSPoint(
			x: 8,
			y: 4
		)
		let point = rail.convert(
			gutterPoint,
			to: controller.view.superview
		)
		let target = try #require(controller.view.hitTest(point))
		#expect(target === rail)
		let transcriptOrigin = controller.conversationScrollView.contentView.bounds.origin
		let railOrigin = scroll.contentView.bounds.origin
		let event = try wheelEvent(
			30,
			window: fixture.window,
			point: rail.convert(
				gutterPoint,
				to: nil
			)
		)
		let content = try #require(fixture.window.contentView)
		let eventPoint = try #require(content.superview).convert(
			event.locationInWindow,
			from: nil
		)
		try #require(content.hitTest(eventPoint) === rail)
		fixture.window.sendEvent(event)
		// DesktopWindow routes this wheel event synchronously to the rail scroll view.
		#expect(scroll.contentView.bounds.origin != railOrigin)
		#expect(controller.conversationScrollView.contentView.bounds.origin == transcriptOrigin)
	}

	@Test func scrollingTheInitialFiftyTurnsRequestsEarlierHistoryOnce() async throws
	{
		let fixture = try await makeFixture(
			turnCount: 50,
			canLoadEarlierTurns: true
		)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let mark = try #require(scroll.documentView?.subviews.last as? TurnNavigationMark)
		let point = mark.convert(
			NSPoint(
				x: 8,
				y: mark.bounds.midY
			),
			to: nil
		)
		var loads = 0
		controller.onLoadEarlierTurnReferences =
		{
			loads += 1
		}
		let transcriptOrigin = controller.conversationScrollView.contentView.bounds.origin
		for _ in 0 ..< 5
		{
			fixture.window.sendEvent(try wheelEvent(
				30,
				window: fixture.window,
				point: point
			))
		}
		#expect(loads == 1)
		#expect(controller.conversationScrollView.contentView.bounds.origin == transcriptOrigin)
		let fade = try #require(scroll.layer?.mask as? CAGradientLayer)
		#expect((fade.colors as? [CGColor])?.map(\.alpha) == [1, 1, 1, 0])
		rail.canLoadEarlierReferences = false
		fixture.window.sendEvent(try wheelEvent(
			30,
			window: fixture.window,
			point: point
		))
		#expect(loads == 1)
		rail.canLoadEarlierReferences = true
		fixture.window.sendEvent(try wheelEvent(
			30,
			window: fixture.window,
			point: point
		))
		#expect(loads == 2)
	}

	@Test func selectingAnUnloadedReferenceRequestsItWithoutChangingTheTranscript() async throws
	{
		let fixture = try await makeFixture(
			turnCount: 25,
			startIndex: 41,
			referenceCount: 66
		)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let mark = try #require(scroll.documentView?.subviews
			.compactMap
			{
				$0 as? TurnNavigationMark
			}.first
			{
				$0.entryID == "turn-4:reference"
			})
		var selected: String?
		controller.onJumpToTurnReference =
		{
			selected = $0
		}
		let entries = controller.entries
		mark.dispatchConfiguredAction()
		let navigationTask = try #require(controller.turnNavigationTask)
		#expect(selected == nil)
		await navigationTask.value
		#expect(selected == "turn-4")
		#expect(controller.entries == entries)
		#expect(rail.activeTurnID == "turn-4")
	}

	@Test func rapidReferenceSelectionFetchesOnlyTheLastTurn() async throws
	{
		let fixture = try await makeFixture(
			turnCount: 25,
			startIndex: 41,
			referenceCount: 66
		)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		var selected: [String] = []
		controller.onJumpToTurnReference =
		{
			selected.append($0)
		}
		let first = try #require(rail.summaries.first
		{
			$0.turnID == "turn-4"
		})
		let last = try #require(rail.summaries.first
		{
			$0.turnID == "turn-5"
		})
		let entries = controller.entries
		rail.onJump?(first)
		let supersededTask = try #require(controller.turnNavigationTask)
		// Replace the pending request before yielding; await actual debounce completion.
		rail.onJump?(last)
		let navigationTask = try #require(controller.turnNavigationTask)
		#expect(selected.isEmpty)
		await supersededTask.value
		await navigationTask.value
		#expect(selected == ["turn-5"])
		#expect(controller.entries == entries)
	}

	@Test func loadedSelectionCancelsPendingReferenceFetch() async throws
	{
		let fixture = try await makeFixture(
			turnCount: 25,
			startIndex: 41,
			referenceCount: 66
		)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let rail = controller.turnNavigationRail
		var selected: [String] = []
		controller.onJumpToTurnReference =
		{
			selected.append($0)
		}
		rail.onJump?(try #require(rail.summaries.first
			{
				$0.turnID == "turn-4"
			}))
		let navigationTask = try #require(controller.turnNavigationTask)
		rail.onJump?(try #require(rail.summaries.first
			{
				$0.turnID == "turn-50"
			}))
		#expect(selected == ["turn-50"])
		await navigationTask.value
		#expect(selected == ["turn-50"])
	}

	@Test func disappearingConversationCancelsPendingReferenceFetch() async throws
	{
		let fixture = try await makeFixture(
			turnCount: 25,
			startIndex: 41,
			referenceCount: 66
		)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		var selected: [String] = []
		controller.onJumpToTurnReference =
		{
			selected.append($0)
		}
		let rail = controller.turnNavigationRail
		rail.onJump?(try #require(rail.summaries.first
			{
				$0.turnID == "turn-4"
			}))
		let navigationTask = try #require(controller.turnNavigationTask)
		controller.viewDidDisappear()
		await navigationTask.value
		#expect(selected.isEmpty)
	}

	@Test func loadedTurnNavigationAnimatesAndFinishesAtTheSelectedTurn() async throws
	{
		let fixture = try await makeFixture(turnCount: 25)
		defer
		{
			tearDown(fixture)
		}
		let controller = fixture.controller
		let summary = try #require(controller.turnNavigationRail.summaries.first
		{
			$0.turnID == "turn-10"
		})
		controller.turnNavigationRail.onJump?(summary)
		#expect(controller.isAnimatingJump)
		// Native animation completion depends on scheduling, not just its configured duration.
		await (try #require(controller.jumpAnimationCompletion)).value
		#expect(!controller.isAnimatingJump)
		#expect(controller.turnNavigationRail.activeTurnID == "turn-10")
		let index = try #require(controller.displayedRows.firstIndex
		{
			$0.sourceEntryID == summary.entryID
		})
		let attributes = try #require(controller.collectionView.collectionViewLayout?
			.layoutAttributesForItem(at: IndexPath(
				item: index,
				section: 0
			)))
		#expect(abs(controller.conversationScrollView.contentView.bounds.minY
				- attributes.frame.minY) < 1)
	}

	private struct Fixture
	{
		let window: NSWindow
		let panes: WindowPaneController
		let controller: ConversationViewController
	}

	private func makeFixture(
		turnCount: Int,
		height: CGFloat = 760,
		canLoadEarlierTurns: Bool = false,
		startIndex: Int = 0,
		referenceCount: Int = 0
	) async throws -> Fixture
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		let panes = WindowPaneController(
			navigation: NavigationViewController(),
			conversation: controller,
			inspector: InspectorViewController(),
			layoutStore: nil
		)
		let window = DesktopWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1100,
				height: height
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = panes.split
		panes.restoreLayout(in: window)
		window.setContentSize(NSSize(
			width: 1100,
			height: height
		))
		panes.didPresentWindow()
		let entries = (startIndex ..< startIndex + turnCount).flatMap
		{
			index in
			[
				ConversationEntry(
					id: "turn-\(index):request",
					kind: .user,
					title: "You",
					body: "\(index)"
				),
				ConversationEntry(
					id: "turn-\(index):reply",
					kind: .agent,
					title: "Codex",
					body: "\(index)"
				),
			]
		}
		var snapshot = ConversationSnapshot(
			projectPath: "/tmp/turn-navigation",
			threads: [],
			selectedThreadID: "thread",
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
		snapshot.turnReferences = (0 ..< referenceCount).map
		{
			ConversationTurnReference(
				id: "turn-\($0)",
				status: "completed"
			)
		}
		snapshot.canLoadEarlierTurnReferences = canLoadEarlierTurns
		controller.render(snapshot)
		await controller.waitForRendering()
		for _ in 0 ..< 4
		{
			panes.split.view.layoutSubtreeIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			controller.collectionView.layoutSubtreeIfNeeded()
			await controller.widthChangeRestoreTask?.value
		}
		return Fixture(
			window: window,
			panes: panes,
			controller: controller
		)
	}

	private func tearDown(_ fixture: Fixture)
	{
		fixture.controller.collectionView.dataSource = nil
		fixture.controller.collectionView.delegate = nil
		fixture.controller.turnNavigationRail.dismissPreview()
		fixture.window.contentViewController = nil
		fixture.window.isReleasedWhenClosed = false
		fixture.window.close()
	}

	private func wheelEvent(
		_ delta: Int32,
		window: NSWindow,
		point: NSPoint
	) throws -> NSEvent
	{
		let wheel = try #require(CGEvent(
			scrollWheelEvent2Source: nil,
			units: .pixel,
			wheelCount: 1,
			wheel1: delta,
			wheel2: 0,
			wheel3: 0
		))
		return LocatedWheelEvent(
			base: try #require(NSEvent(cgEvent: wheel)),
			point: point,
			windowNumber: window.windowNumber
		)
	}

	private final class LocatedWheelEvent: NSEvent
	{
		let base: NSEvent
		let point: NSPoint
		let number: Int

		init(
			base: NSEvent,
			point: NSPoint,
			windowNumber: Int
		)
		{
			self.base = base
			self.point = point
			self.number = windowNumber
			super.init()
		}

		@available(
			*,
			unavailable
		)
		required init?(coder: NSCoder)
		{
			fatalError("init(coder:) has not been implemented")
		}

		override var type: NSEvent.EventType
		{
			.scrollWheel
		}
		override var locationInWindow: NSPoint
		{
			point
		}
		override var windowNumber: Int
		{
			number
		}
		override var hasPreciseScrollingDeltas: Bool
		{
			base.hasPreciseScrollingDeltas
		}
		override var scrollingDeltaY: CGFloat
		{
			base.scrollingDeltaY
		}
	}
}
