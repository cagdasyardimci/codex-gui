import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnNavigationRailAppearanceTests
{
	@Test func highlightChangesOnlyInvalidateTheOldAndNewMarks() throws
	{
		let summaries = summaries(count: 96)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		let marks = try marks(in: rail)
		var previous: Int?
		let highlights: [Int?] = [0, 1, 4, 30, 31, 95, 94, nil]
		for next in highlights
		{
			updates.reset()
			rail.updateActiveTurn(next.map
			{
				summaries[$0].turnID
			})
			expectAppearance(
				marks,
				highlighted: next
			)
			expectInvalidation(
				updates,
				markCount: marks.count,
				previous: previous,
				next: next
			)
			previous = next
		}
	}

	@Test func marksUseDesktopSpacingAndConstantWidth() throws
	{
		let rail = makeRail(
			summaries(count: 24),
			updates: AppearanceUpdates()
		)
		let marks = try marks(in: rail)
		#expect(marks.allSatisfy
		{
			$0.frame.height == 10 && $0.lineWidth == 6
		})
		#expect(zip(
			marks,
			marks.dropFirst()
		).allSatisfy
		{
			pair in pair.0.frame.midY - pair.1.frame.midY == 10
		})
		rail.updateActiveTurn(rail.summaries.last?.turnID)
		#expect(marks.allSatisfy
		{
			$0.lineWidth == 6
		})
	}

	@Test(
		arguments: [24, 61, 62, 63, 66, 96],
		[280, 900]
	)
	func railHeightStopsAtSixtyTwoMarksAndFitsSmallerWindows(
		turnCount: Int,
		availableHeight: Int
	) throws
	{
		let rail = makeRail(
			summaries(count: turnCount),
			updates: AppearanceUpdates(),
			height: CGFloat(availableHeight)
		)
		let scrollView = try #require(rail.subviews.first as? NSScrollView)
		let expectedHeight = min(
			CGFloat(availableHeight),
			620,
			CGFloat(turnCount) * 10
		)
		#expect(scrollView.frame.height == expectedHeight)
		#expect(scrollView.frame.midY == rail.bounds.midY)
		#expect(scrollView.documentView?.frame.height == CGFloat(turnCount) * min(
			10,
			CGFloat(availableHeight) / CGFloat(min(
				62,
				turnCount
			))
		))
	}

	@Test(arguments: [24, 61, 62, 63, 66, 96])
	func wheelScrollsOverflowingMarksWithoutForwardingInput(turnCount: Int) async throws
	{
		_ = NSApplication.shared
		let rail = makeRail(
			summaries(count: turnCount),
			updates: AppearanceUpdates(),
			height: 900
		)
		let window = NSWindow(
			contentRect: rail.frame,
			styleMask: .borderless,
			backing: .buffered,
			defer: false
		)
		window.contentView = rail
		defer
		{
			window.contentView = nil
		}
		let scrollView = try #require(rail.subviews.first as? NSScrollView)
		let origin = scrollView.contentView.bounds.origin
		let unhandled = WheelReceiver()
		rail.nextResponder = unhandled
		var moved = false
		for delta: Int32 in [30, -30]
		{
			scrollView.scrollWheel(with: try wheelEvent(delta))
			try await Task.sleep(for: .milliseconds(30))
			moved = moved || scrollView.contentView.bounds.origin != origin
		}
		if turnCount > 62
		{
			#expect(unhandled.events == 0)
			#expect(moved)
			#expect(scrollView.verticalScrollElasticity == .none)
			for _ in 0 ..< 4
			{
				scrollView.scrollWheel(with: try wheelEvent(-1200))
			}
			try await Task.sleep(for: .milliseconds(30))
			#expect(unhandled.events == 0)
			let document = try #require(scrollView.documentView)
			#expect(scrollView.contentView.bounds.minY >= 0)
			#expect(scrollView.contentView.bounds.maxY <= document.bounds.maxY)
		}
		else
		{
			#expect(unhandled.events == 0)
			#expect(!moved)
		}
	}

	@Test(arguments: [true, false])
	func wheelScrollsPreciselyAndClampsWithoutNativeWindowDispatch(precise: Bool) throws
	{
		_ = NSApplication.shared
		let rail = makeRail(
			summaries(count: 96),
			updates: AppearanceUpdates(),
			height: 900
		)
		rail.updateActiveTurn("turn-95")
		rail.layoutSubtreeIfNeeded()
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		#expect(rail.window == nil)
		let units: CGScrollEventUnit = precise ? .pixel : .line
		rail.scrollWheel(with: try wheelEvent(
			precise ? 30 : 3,
			units: units
		))
		#expect(scroll.contentView.bounds.origin.y == 30)
		rail.scrollWheel(with: try wheelEvent(
			-1200,
			units: units
		))
		#expect(scroll.contentView.bounds.origin.y == 0)
		rail.scrollWheel(with: try wheelEvent(
			1200,
			units: units
		))
		#expect(scroll.contentView.bounds.maxY == scroll.documentView?.bounds.maxY)
	}

	@Test func hiddenTurnsFadeAtTheirViewportEdgeAndFittingTurnsStayOpaque() throws
	{
		let rail = makeRail(
			summaries(count: 96),
			updates: AppearanceUpdates(),
			height: 900
		)
		rail.updateActiveTurn("turn-95")
		rail.layoutSubtreeIfNeeded()
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let fade = try #require(scroll.layer?.mask as? CAGradientLayer)
		#expect((fade.colors as? [CGColor])?.map(\.alpha) == [1, 1, 1, 0])
		#expect(fade.startPoint.y == (scroll.isFlipped ? 1 : 0))
		#expect(fade.endPoint.y == (scroll.isFlipped ? 0 : 1))
		rail.scrollWheel(with: try wheelEvent(100))
		#expect((fade.colors as? [CGColor])?.map(\.alpha) == [0, 1, 1, 0])
		rail.scrollWheel(with: try wheelEvent(1200))
		#expect((fade.colors as? [CGColor])?.map(\.alpha) == [0, 1, 1, 1])
		#expect(fade.frame == scroll.bounds)
		rail.render(summaries(count: 24))
		rail.layoutSubtreeIfNeeded()
		#expect(scroll.layer?.mask == nil)
	}

	@Test func loadingEarlierTurnsKeepsTheManuallyScrolledRailPosition() throws
	{
		let loaded = summaries(count: 96)
		let rail = makeRail(
			loaded,
			updates: AppearanceUpdates(),
			height: 900
		)
		rail.updateActiveTurn("turn-95")
		rail.layoutSubtreeIfNeeded()
		rail.scrollWheel(with: try wheelEvent(200))
		let scroll = try #require(rail.subviews.first as? NSScrollView)
		let origin = scroll.contentView.bounds.origin
		rail.render(summaries(
			count: 50,
			start: -50
		) + loaded)
		rail.layoutSubtreeIfNeeded()
		#expect(scroll.contentView.bounds.origin == origin)
		#expect(rail.activeTurnID == "turn-95")
	}

	@Test func activeMarkStaysVisibleWithoutUndoingManualRailScrolling() throws
	{
		let rail = makeRail(
			summaries(count: 96),
			updates: AppearanceUpdates(),
			height: 900
		)
		let scrollView = try #require(rail.subviews.first as? NSScrollView)
		let marks = try marks(in: rail)
		rail.updateActiveTurn("turn-95")
		rail.layoutSubtreeIfNeeded()
		#expect(scrollView.contentView.bounds.contains(marks[95].frame))
		rail.updateActiveTurn("turn-34")
		rail.layoutSubtreeIfNeeded()
		#expect(scrollView.contentView.bounds.maxY - marks[34].frame.maxY >= 40)
		rail.updateActiveTurn("turn-0")
		rail.layoutSubtreeIfNeeded()
		#expect(scrollView.contentView.bounds.contains(marks[0].frame))
		scrollView.contentView.scroll(to: .zero)
		scrollView.reflectScrolledClipView(scrollView.contentView)
		rail.updateActiveTurn("turn-0")
		rail.layoutSubtreeIfNeeded()
		#expect(scrollView.contentView.bounds.origin == .zero)
		#expect(rail.activeTurnID == "turn-0")
		rail.updateActiveTurn("turn-1")
		rail.layoutSubtreeIfNeeded()
		#expect(scrollView.contentView.bounds.contains(marks[1].frame))
	}

	@Test func unchangedResolvedHighlightDoesNotRedrawForRepeatedOrUnknownTurnIDs() throws
	{
		let summaries = summaries(count: 96)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		let marks = try marks(in: rail)
		for turnID in ["missing", "another-missing", nil]
		{
			updates.reset()
			rail.updateActiveTurn(turnID)
			#expect(rail.activeTurnID == turnID)
			#expect(updates.indices.isEmpty)
			expectAppearance(
				marks,
				highlighted: nil
			)
		}
		rail.updateActiveTurn(summaries[40].turnID)
		updates.reset()
		rail.updateActiveTurn(summaries[40].turnID)
		#expect(updates.indices.isEmpty)
		expectAppearance(
			marks,
			highlighted: 40
		)
	}

	@Test func hoverPrecedesActiveTurnAndExitRestoresTheLatestActiveIdentity() throws
	{
		let summaries = summaries(count: 96)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		defer
		{
			rail.dismissPreview()
		}
		let marks = try marks(in: rail)
		let enter = try hoverEvent(.mouseEntered)
		let exit = try hoverEvent(.mouseExited)
		rail.updateActiveTurn(summaries[10].turnID)
		updates.reset()
		marks[50].mouseEntered(with: enter)
		expectAppearance(
			marks,
			highlighted: 50
		)
		expectInvalidation(
			updates,
			markCount: marks.count,
			previous: 10,
			next: 50
		)
		updates.reset()
		rail.updateActiveTurn(summaries[70].turnID)
		marks[50].mouseEntered(with: enter)
		#expect(rail.activeTurnID == summaries[70].turnID)
		#expect(updates.indices.isEmpty)
		expectAppearance(
			marks,
			highlighted: 50
		)
		marks[51].mouseEntered(with: enter)
		updates.reset()
		marks[50].mouseExited(with: exit)
		#expect(updates.indices.isEmpty)
		expectAppearance(
			marks,
			highlighted: 51
		)
		marks[51].mouseExited(with: exit)
		expectAppearance(
			marks,
			highlighted: 70
		)
		expectInvalidation(
			updates,
			markCount: marks.count,
			previous: 51,
			next: 70
		)
		marks[50].mouseEntered(with: enter)
		updates.reset()
		rail.updateActiveTurn("missing")
		#expect(rail.activeTurnID == "missing")
		#expect(updates.indices.isEmpty)
		marks[50].mouseExited(with: exit)
		expectAppearance(
			marks,
			highlighted: nil
		)
		expectInvalidation(
			updates,
			markCount: marks.count,
			previous: 50,
			next: nil
		)
	}

	@Test func rebuiltMarksInitializeFullyWhenTheResolvedHighlightStaysTheSame() throws
	{
		let summaries = summaries(count: 32)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		#expect(updates.indices == Array(summaries.indices))
		rail.updateActiveTurn(summaries[10].turnID)
		let oldMarks = try marks(in: rail)
		var replacements = self.summaries(
			count: 32,
			start: 100
		)
		replacements[10] = summaries[10]
		updates.reset()
		rail.render(replacements)
		let rebuilt = try marks(in: rail)
		#expect(oldMarks.allSatisfy
		{
			$0.superview == nil
		})
		#expect(updates.indices == Array(rebuilt.indices))
		expectAppearance(
			rebuilt,
			highlighted: 10
		)
		rail.updateActiveTurn(nil)
		updates.reset()
		rail.render(self.summaries(
			count: 32,
			start: 200
		))
		let withoutHighlight = try marks(in: rail)
		#expect(updates.indices == Array(withoutHighlight.indices))
		expectAppearance(
			withoutHighlight,
			highlighted: nil
		)
	}

	@Test func historyPrependsClearHoverAndTrackActiveIdentityThroughReordersAndRemoval() throws
	{
		let summaries = summaries(count: 96)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		defer
		{
			rail.dismissPreview()
		}
		rail.updateActiveTurn(summaries[70].turnID)
		let oldMarks = try marks(in: rail)
		oldMarks[20].mouseEntered(with: try hoverEvent(.mouseEntered))
		let earlier = self.summaries(
			count: 24,
			start: -24
		)
		updates.reset()
		rail.render(earlier + summaries)
		let prepended = try marks(in: rail)
		#expect(updates.indices == Array(prepended.indices))
		#expect(rail.activeTurnID == summaries[70].turnID)
		#expect(prepended[94].entryID == summaries[70].entryID)
		expectAppearance(
			prepended,
			highlighted: 94
		)
		updates.reset()
		rail.render(Array(summaries.reversed()))
		#expect(updates.indices == Array(summaries.indices))
		expectAppearance(
			try marks(in: rail),
			highlighted: 25
		)
		updates.reset()
		rail.render([summaries[0]])
		#expect(updates.indices == [0])
		expectAppearance(
			try marks(in: rail),
			highlighted: nil
		)
		updates.reset()
		rail.render([])
		#expect(updates.indices.isEmpty)
		#expect(try marks(in: rail).isEmpty)
		#expect(rail.isHidden)
		#expect(rail.activeTurnID == summaries[70].turnID)
		rail.render(summaries)
		expectAppearance(
			try marks(in: rail),
			highlighted: 70
		)
	}

	@Test func streamingReplyKeepsMarkIdentityFocusGeometryAndCurrentJumpTarget() throws
	{
		_ = NSApplication.shared
		let summaries = summaries(count: 32)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			summaries,
			updates: updates
		)
		let window = NSWindow(
			contentRect: rail.frame,
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = rail
		defer
		{
			window.close()
		}
		let initial = try marks(in: rail)
		let frames = initial.map(\.frame)
		let focused = initial[10]
		#expect(window.makeFirstResponder(focused))
		#expect(window.firstResponder === focused)
		rail.updateActiveTurn(summaries[10].turnID)
		updates.reset()
		var updated = summaries
		updated[10].reply = "The streamed reply grew."
		rail.render(updated)
		let streamed = try marks(in: rail)
		#expect(zip(
			initial,
			streamed
		).allSatisfy
		{
			pair in pair.0 === pair.1
		})
		#expect(streamed.map(\.frame) == frames)
		#expect(window.firstResponder === focused)
		#expect(updates.indices.isEmpty)
		#expect(focused.accessibilityLabel() == "Jump to turn: \(summaries[10].title)")
		var jumped: ConversationTurnSummary?
		rail.onJump =
		{
			jumped = $0
		}
		focused.performClick(nil)
		#expect(jumped == updated[10])
	}

	@Test func identityIndicesKeepFirstMatchesAndRefreshWhenTurnIDsChange() throws
	{
		let first = ConversationTurnSummary(
			turnID: "first",
			entryID: "shared",
			title: "First",
			reply: "First reply"
		)
		let second = ConversationTurnSummary(
			turnID: "second",
			entryID: "second:request",
			title: "Second",
			reply: "Second reply"
		)
		let duplicateTurn = ConversationTurnSummary(
			turnID: "first",
			entryID: "first:other-request",
			title: "Duplicate turn",
			reply: "Other reply"
		)
		let duplicateEntry = ConversationTurnSummary(
			turnID: "second",
			entryID: "shared",
			title: "Duplicate entry",
			reply: "Other entry reply"
		)
		let updates = AppearanceUpdates()
		let rail = makeRail(
			[first, second, duplicateTurn, duplicateEntry],
			updates: updates
		)
		defer
		{
			rail.dismissPreview()
		}
		let initial = try marks(in: rail)
		rail.updateActiveTurn("first")
		expectAppearance(
			initial,
			highlighted: 0
		)
		rail.updateActiveTurn("second")
		expectAppearance(
			initial,
			highlighted: 1
		)
		initial[3].mouseEntered(with: try hoverEvent(.mouseEntered))
		expectAppearance(
			initial,
			highlighted: 0
		)
		var jumped: ConversationTurnSummary?
		rail.onJump =
		{
			jumped = $0
		}
		initial[3].performClick(nil)
		#expect(jumped == first)
		initial[3].mouseExited(with: try hoverEvent(.mouseExited))
		rail.updateActiveTurn("first")
		let renamed = ConversationTurnSummary(
			turnID: "renamed",
			entryID: first.entryID,
			title: first.title,
			reply: first.reply
		)
		rail.render([renamed, second, duplicateTurn, duplicateEntry])
		let updated = try marks(in: rail)
		#expect(zip(
			initial,
			updated
		).allSatisfy
		{
			pair in pair.0 === pair.1
		})
		expectAppearance(
			updated,
			highlighted: 2
		)
		initial[3].performClick(nil)
		#expect(jumped == renamed)
	}

	private func summaries(
		count: Int,
		start: Int = 0
	) -> [ConversationTurnSummary]
	{
		(start ..< start + count).map
		{
			ConversationTurnSummary(
				turnID: "turn-\($0)",
				entryID: "turn-\($0):request",
				title: "Request \($0)",
				reply: "Reply \($0)"
			)
		}
	}

	private func makeRail(
		_ summaries: [ConversationTurnSummary],
		updates: AppearanceUpdates,
		height: CGFloat = 600
	) -> TurnNavigationRail
	{
		let rail = TurnNavigationRail(frame: NSRect(
			x: 0,
			y: 0,
			width: 40,
			height: height
		))
		rail.onMarkAppearanceUpdate =
		{
			updates.indices.append($0)
		}
		rail.render(summaries)
		rail.layoutSubtreeIfNeeded()
		return rail
	}

	private func marks(in rail: TurnNavigationRail) throws -> [TurnNavigationMark]
	{
		let scrollView = try #require(rail.subviews.first as? NSScrollView)
		let document = try #require(scrollView.documentView)
		let marks = document.subviews.compactMap
		{
			$0 as? TurnNavigationMark
		}
		#expect(marks.count == rail.summaries.count)
		return marks
	}

	private func hoverEvent(_ type: NSEvent.EventType) throws -> NSEvent
	{
		try #require(NSEvent.enterExitEvent(
			with: type,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}

	private func wheelEvent(
		_ delta: Int32,
		units: CGScrollEventUnit = .pixel
	) throws -> NSEvent
	{
		let wheel = try #require(CGEvent(
			scrollWheelEvent2Source: nil,
			units: units,
			wheelCount: 1,
			wheel1: delta,
			wheel2: 0,
			wheel3: 0
		))
		return try #require(NSEvent(cgEvent: wheel))
	}

	@MainActor
	private final class WheelReceiver: NSResponder
	{
		var events = 0

		override func scrollWheel(with _: NSEvent)
		{
			events += 1
		}
	}

	@MainActor
	private final class AppearanceUpdates
	{
		var indices: [Int] = []

		func reset()
		{
			indices.removeAll(keepingCapacity: true)
		}
	}

	private func expectAppearance(
		_ marks: [TurnNavigationMark],
		highlighted: Int?
	)
	{
		#expect(marks.allSatisfy
		{
			$0.lineWidth == 6
		})
		#expect(marks.map(\.isEmphasized) == marks.indices.map
		{
			$0 == highlighted
		})
	}

	private func expectInvalidation(
		_ updates: AppearanceUpdates,
		markCount: Int,
		previous: Int?,
		next: Int?
	)
	{
		let affected = Set([previous, next].compactMap
		{
			$0
		})
		#expect(affected.allSatisfy
		{
			(0 ..< markCount).contains($0)
		})
		#expect(Set(updates.indices) == affected)
	}
}
