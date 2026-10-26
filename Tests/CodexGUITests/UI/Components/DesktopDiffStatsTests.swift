import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopDiffStatsTests
{
	@Test func unavailableTotalsReplacePriorCountsAndTreeZeroSuppressionRecovers()
	{
		_ = NSApplication.shared
		let counts = DesktopDiffStats.Counts(
			additions: 12345,
			deletions: 0
		)
		let toolbar = DesktopDiffStats(
			counts: counts,
			presentation: .toolbar
		)
		#expect(toolbar.additionsLabel.stringValue == "+12,345")
		#expect(toolbar.deletionsLabel.stringValue == "-0")
		toolbar.update(nil)
		#expect(toolbar.additionsLabel.stringValue == "—")
		#expect(toolbar.deletionsLabel.stringValue == "—")
		toolbar.update(DesktopDiffStats.Counts(
			additions: 3,
			deletions: 2
		))
		#expect(toolbar.additionsLabel.stringValue == "+3")
		#expect(toolbar.deletionsLabel.stringValue == "-2")

		let tree = DesktopDiffStats(
			counts: counts,
			presentation: .fileTree
		)
		#expect(tree.additionsLabel.stringValue == "+12345")
		#expect(!tree.additionsLabel.isHidden)
		#expect(tree.deletionsLabel.isHidden)
		tree.update(DesktopDiffStats.Counts(
			additions: 0,
			deletions: 8
		))
		#expect(tree.additionsLabel.isHidden)
		#expect(!tree.deletionsLabel.isHidden)
		#expect(tree.deletionsLabel.stringValue == "-8")

		let summary = DesktopDiffStats(
			counts: counts,
			presentation: .summary
		)
		#expect(summary.additionsLabel.stringValue == "+12,345")
		#expect(summary.additionsLabel.accessibilityLabel() == "12345 additions")
		#expect(summary.deletionsLabel.accessibilityLabel() == "0 deletions")
		#expect(!summary.deletionsLabel.isHidden)
		let capsule = DesktopDiffStats.attributedValue(
			counts,
			presentation: .turnSummary
		)
		#expect(capsule.string == " +12345 -0")
		#expect((capsule.attribute(
			.font,
			at: 0,
			effectiveRange: nil
		) as? NSFont)?.pointSize == 13)

	}
}
