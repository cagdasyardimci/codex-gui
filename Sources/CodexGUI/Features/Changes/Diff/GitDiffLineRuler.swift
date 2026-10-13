import AppKit

@MainActor
final class GitDiffLineRuler: NSRulerView
{
	private static let lineNumberVerticalOffset: CGFloat = 2

	private let rows: [GitDiffRow]
	private let font: NSFont
	private let gutterMode: GitUnifiedCodeView.GutterMode
	private weak var source: GitDiffTextView?

	init(
		scrollView: NSScrollView,
		source: GitDiffTextView,
		rows: [GitDiffRow],
		font: NSFont,
		gutterMode: GitUnifiedCodeView.GutterMode
	)
	{
		self.rows = rows
		self.font = font
		self.gutterMode = gutterMode
		self.source = source
		super.init(
			scrollView: scrollView,
			orientation: .verticalRuler
		)
		clientView = source
		let maximumLineNumber = rows.flatMap
		{
			[$0.oldLine ?? 0, $0.newLine ?? 0]
		}.max() ?? 0
		let lineNumberWidth = (String(maximumLineNumber) as NSString)
			.size(withAttributes: [.font: font]).width
		if gutterMode == .unified
		{
			ruleThickness = max(
				52,
				lineNumberWidth + 24
			)
			setAccessibilityLabel(
				"Old line numbers for deletions and new line numbers for additions"
			)
		}
		else
		{
			ruleThickness = max(
				42,
				lineNumberWidth + 22
			)
			let side = gutterMode == .old ? "old" : "new"
			setAccessibilityLabel("Logical \(side) source line numbers and change markers")
		}
	}

	required init(coder: NSCoder)
	{
		fatalError("init(coder:) has not been implemented")
	}
	override var isFlipped: Bool
	{
		true
	}

	override func drawHashMarksAndLabels(in rect: NSRect)
	{
		// AppKit can pass the scroll viewport's dirty rect, wider than this ruler.
		// Keep the gutter background and markers from painting over source text.
		let gutterRect = rect.intersection(bounds)
		guard !gutterRect.isEmpty
		else
		{
			return
		}
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSBezierPath(rect: bounds).addClip()
		AppKitColorTokens.canvas.setFill()
		gutterRect.fill()
		guard let source
		else
		{
			return
		}
		let sourceDirtyRect = source.convert(
			gutterRect,
			from: self
		).offsetBy(
			dx: 0,
			dy: -Self.lineNumberVerticalOffset
		)
		for index in source.visualRowIndices(
			from: sourceDirtyRect.minY,
			through: sourceDirtyRect.maxY
		)
		{
			let row = rows[index]
			let sourceRect = source.visualRowRect(at: index)
			let position = convert(
				NSPoint(
					x: 0,
					y: sourceRect.minY + Self.lineNumberVerticalOffset
				),
				from: source
			)
			guard position.y + sourceRect.height >= rect.minY, position.y <= rect.maxY
			else
			{
				continue
			}
			let color: NSColor = row.kind == .addition ? .systemGreen : row
				.kind == .deletion ? .systemRed : .secondaryLabelColor
			if row.kind == .addition || row.kind == .deletion
			{
				color.withAlphaComponent(0.06).setFill()
				NSRect(
					x: 0,
					y: position.y - Self.lineNumberVerticalOffset,
					width: ruleThickness,
					height: sourceRect.height
				).fill()
				let rail = NSRect(
					x: 0,
					y: position.y - Self.lineNumberVerticalOffset,
					width: 3,
					height: sourceRect.height
				)
				color.setFill()
				if row.kind == .deletion
				{
					for y in stride(
						from: rail.minY,
						to: rail.maxY,
						by: 3
					)
					{
						NSRect(
							x: rail.minX,
							y: y,
							width: rail.width,
							height: 1
						).fill()
					}
				}
				else
				{
					rail.fill()
				}
			}
			let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
			func draw(
				_ text: String,
				right: CGFloat
			)
			{
				let string = text as NSString
				let width = string.size(withAttributes: attributes).width
				string.draw(
					at: NSPoint(
						x: right - width,
						y: position.y
					),
					withAttributes: attributes
				)
			}
			switch gutterMode
			{
			case .unified:
				draw(
					(row.kind == .deletion ? row.oldLine : (row.newLine ?? row.oldLine))
						.map(String.init) ?? "",
					right: ruleThickness - 9
				)
			case .old:
				draw(
					row.oldLine.map(String.init) ?? "",
					right: ruleThickness - 20
				)
			case .new:
				draw(
					row.newLine.map(String.init) ?? "",
					right: ruleThickness - 20
				)
			}
			if gutterMode != .unified
			{
				draw(
					row.kind == .addition ? "+" : row.kind == .deletion ? "−" : "",
					right: ruleThickness - 5
				)
			}
		}
	}
}
