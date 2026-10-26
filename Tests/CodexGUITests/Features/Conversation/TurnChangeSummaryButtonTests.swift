import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct TurnChangeSummaryButtonTests
{
	@Test func previousTurnCountsExplainTheirSource() throws
	{
		var snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		snapshot.reportedGitTurnID = "previous"
		let summary = try #require(ConversationTurnChangeSummary(snapshot))
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "2 files changed +3 -1")
		#expect(button.toolTip?.contains("Previous editing turn") == true)
		#expect(button.accessibilityLabel()?.contains("Previous editing turn") == true)
	}

	@Test(arguments: [GitComparisonFailure.lastTurnUnavailable,
						.oversized,
						.repositoryUnavailable,
						.cancelled,
						.failed("Preview failed")])
	func failuresKeepTheCountsWithoutDisplayingTheError(_ failure: GitComparisonFailure) throws
	{
		let snapshot = ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		let request = try #require(snapshot.runningGitReviewRequest(
			owner: FeaturePresentationOwner(snapshot)
		))
		let summary = try #require(ConversationTurnChangeSummary(
			result: .unavailable(failure),
			request: request
		))
		let button = TurnChangeSummaryButton()
		button.render(summary)
		#expect(button.attributedTitle.string == "2 files changed +3 -1")
		#expect(button.toolTip?.contains(failure.message) == false)
		#expect(button.accessibilityLabel()?.contains(failure.message) == false)
		button.render(ConversationTurnChangeSummary(unavailable: failure))
		#expect(button.attributedTitle.string == "0 files changed +0 -0")
		#expect(button.toolTip?.contains(failure.message) == false)
		#expect(button.accessibilityLabel()?.contains(failure.message) == false)
	}

	@Test(.appKitIsolation)
	func retainedSummaryRefreshesTitleAndBorderWithoutRerendering() throws
	{
		_ = NSApplication.shared
		let summary = try #require(ConversationTurnChangeSummary(
			ConversationTurnChangeSummaryTestFixture.makeSnapshot()
		))
		let button = TurnChangeSummaryButton()
		button.frame = NSRect(
			x: 20,
			y: 20,
			width: 260,
			height: 34
		)
		button.render(summary)
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 300,
				height: 80
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView?.addSubview(button)
		defer
		{
			window.close()
		}
		let cell = button.cell
		#expect(window.makeFirstResponder(button))
		for name in [NSAppearance.Name.aqua, .darkAqua, .aqua]
		{
			window.appearance = try #require(NSAppearance(named: name))
			window.displayIfNeeded()
			let title = button.attributedTitle
			#expect(title.string == "2 files changed +3 -1")
			for (offset, expected) in [(0, NSColor.secondaryLabelColor),
										(15, .systemGreen),
										(18, .systemRed)]
			{
				let actual = try #require(title.attribute(
					.foregroundColor,
					at: offset,
					effectiveRange: nil
				) as? NSColor)
				#expect(actual.cgColor.components == AppKitColorResolution.resolvedCGColor(
					expected,
					for: button
				).components)
			}
			#expect(button.layer?.borderColor?.components
				== AppKitColorResolution.resolvedCGColor(
					AppKitColorTokens.border,
					for: button
				).components)
			#expect(button.cell === cell)
			#expect(window.firstResponder === button)
		}
	}

	private func change(_ diff: String) -> FileChange
	{
		FileChange(json: ["path": "same.swift", "kind": "update", "diff": diff])!
	}
}
