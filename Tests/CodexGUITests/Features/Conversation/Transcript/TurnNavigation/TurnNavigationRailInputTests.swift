import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationRailInputTests
{

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
		let rail = controller.transcript.turnNavigationRail
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
		controller.transcript.onJumpToTurnReference =
		{
			selected = $0
		}
		let entries = controller.transcript.entries
		let loaded = try #require(rail.summaries.first
		{
			$0.isContentLoaded
		})
		controller.transcript.jumpToEntry(id: loaded.entryID)
		let supersededMotion = try #require(controller.transcript.jumpAnimationCompletion)
		let origin = controller.transcript.conversationScrollView.contentView.bounds.origin
		mark.dispatchConfiguredAction()
		let navigationTask = try #require(controller.transcript.turnNavigationTask)
		#expect(supersededMotion.isCancelled)
		#expect(!controller.transcript.isAnimatingJump)
		#expect(controller.transcript.jumpAnimationCompletion == nil)
		#expect(selected == nil)
		await supersededMotion.value
		#expect(controller.transcript.conversationScrollView.contentView.bounds.origin == origin)
		await navigationTask.value
		#expect(controller.transcript.conversationScrollView.contentView.bounds.origin == origin)
		#expect(selected == "turn-4")
		#expect(controller.transcript.entries == entries)
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
		let rail = controller.transcript.turnNavigationRail
		var selected: [String] = []
		controller.transcript.onJumpToTurnReference =
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
		let entries = controller.transcript.entries
		rail.onJump?(first)
		let supersededTask = try #require(controller.transcript.turnNavigationTask)
		// Replace the pending request before yielding; await actual debounce completion.
		rail.onJump?(last)
		let navigationTask = try #require(controller.transcript.turnNavigationTask)
		#expect(selected.isEmpty)
		await supersededTask.value
		await navigationTask.value
		#expect(selected == ["turn-5"])
		#expect(controller.transcript.entries == entries)
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
		let rail = controller.transcript.turnNavigationRail
		var selected: [String] = []
		controller.transcript.onJumpToTurnReference =
		{
			selected.append($0)
		}
		rail.onJump?(try #require(rail.summaries.first
			{
				$0.turnID == "turn-4"
			}))
		let navigationTask = try #require(controller.transcript.turnNavigationTask)
		rail.onJump?(try #require(rail.summaries.first
			{
				$0.turnID == "turn-50"
			}))
		#expect(selected == ["turn-50"])
		await navigationTask.value
		#expect(selected == ["turn-50"])
	}

	@Test(.timeLimit(.minutes(1)))
	func parentJumpCallbackReplacementRestoresLocalLoadedTurnNavigation() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let fixture = try await makeFixture(
				turnCount: 12,
				presentWindow: true
			)
			defer
			{
				tearDown(fixture)
			}
			let controller = fixture.controller
			let transcript = controller.transcript
			let rail = transcript.turnNavigationRail
			let local = try #require(rail.summaries.first
			{
				$0.turnID == "turn-2"
			})
			let routed = try #require(rail.summaries.first
			{
				$0.turnID == "turn-4"
			})
			let restored = try #require(rail.summaries.first
			{
				$0.turnID == "turn-6"
			})
			let localIndex = try #require(transcript.displayedRows.firstIndex
			{
				$0.sourceEntryID == local.entryID
			})
			let restoredIndex = try #require(transcript.displayedRows.firstIndex
			{
				$0.sourceEntryID == restored.entryID
			})
			rail.onJump?(local)
			#expect(transcript.collectionView.selectionIndexPaths == [IndexPath(
				item: localIndex,
				section: 0
			)])
			await transcript.jumpAnimationCompletion?.value

			var requested: [String] = []
			controller.onJumpToTurnReference =
			{
				requested.append($0)
			}
			rail.onJump?(routed)
			#expect(requested == ["turn-4"])
			#expect(transcript.collectionView.selectionIndexPaths == [IndexPath(
				item: localIndex,
				section: 0
			)])

			controller.onJumpToTurnReference = nil
			transcript.collectionView.deselectAll(nil)
			rail.onJump?(restored)
			#expect(requested == ["turn-4"])
			#expect(transcript.collectionView.selectionIndexPaths == [IndexPath(
				item: restoredIndex,
				section: 0
			)])
			await transcript.jumpAnimationCompletion?.value
		}
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
		referenceCount: Int = 0,
		presentWindow: Bool = false
	) async throws -> Fixture
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		controller.transcript.shouldReduceMotion =
		{
			false
		}
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
		window.prepareForTesting()
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
			controller.transcript.collectionView.layoutSubtreeIfNeeded()
			await controller.transcript.widthChangeRestoreTask?.value
		}
		if presentWindow
		{
			window.orderFront(nil)
			window.layoutIfNeeded()
			window.displayIfNeeded()
			#expect(window.isVisible)
		}
		return Fixture(
			window: window,
			panes: panes,
			controller: controller
		)
	}

	private func tearDown(_ fixture: Fixture)
	{
		fixture.controller.transcript.collectionView.dataSource = nil
		fixture.controller.transcript.collectionView.delegate = nil
		fixture.controller.transcript.turnNavigationRail.dismissPreview()
		fixture.window.contentViewController = nil
		fixture.window.prepareForTesting()
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
