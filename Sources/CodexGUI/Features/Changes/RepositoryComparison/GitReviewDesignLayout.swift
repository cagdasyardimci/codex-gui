import AppKit

enum GitReviewDesignLayout
{
	/// Proposed local presentation policy; the reference does not specify a threshold.
	static let largeFileCount = 20
	static let largeChangedLineCount = 2_000

	static func isLarge(_ snapshot: GitComparisonSnapshot) -> Bool
	{
		guard !snapshot.files.isEmpty
		else
		{
			return false
		}
		let hasManyFiles = snapshot.files.count >= largeFileCount
		if hasManyFiles
		{
			return true
		}
		let changedLineCount = snapshot.additions + snapshot.deletions
		return changedLineCount >= largeChangedLineCount
	}
}

@MainActor
final class GitReviewTreeCell: NSStackView
{
	var guideDepth = 0

	override func draw(_ dirtyRect: NSRect)
	{
		super.draw(dirtyRect)
		AppKitColorTokens.border.setStroke()
		for depth in 0 ..< guideDepth
		{
			let x = CGFloat(16 + depth * 16)
			let guide = NSBezierPath()
			guide.move(to: NSPoint(
				x: x,
				y: bounds.minY
			))
			guide.line(to: NSPoint(
				x: x,
				y: bounds.maxY
			))
			guide.lineWidth = 1
			guide.stroke()
		}
	}
}

@MainActor
final class GitReviewFileRowView: NSTableRowView
{
	// Selection uses the canvas with an outline, so labels keep their normal colors.
	override var interiorBackgroundStyle: NSView.BackgroundStyle
	{
		.normal
	}

	override func drawSelection(in dirtyRect: NSRect)
	{
		guard isSelected
		else
		{
			return
		}
		let outline = NSBezierPath(
			roundedRect: bounds.insetBy(
				dx: 1,
				dy: 1
			),
			xRadius: 6,
			yRadius: 6
		)
		AppKitColorTokens.canvas.setFill()
		outline.fill()
		NSColor.systemBlue.setStroke()
		outline.lineWidth = 1
		outline.stroke()
	}
}
