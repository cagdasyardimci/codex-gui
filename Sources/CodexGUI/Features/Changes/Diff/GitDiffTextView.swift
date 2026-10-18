import AppKit

@MainActor
final class GitDiffTextView: SourceTextView
{
	var rows: [GitDiffRow] = []
	{
		didSet
		{
			var offset = 0
			rowStartOffsets = rows.map
			{
				row in
				defer
				{
					offset += (row.text as NSString).length + 1
				}
				return offset
			}
			invalidateVisualRowGeometry()
		}
	}
	var placeholderIndices: Set<Int> = []
	var drawsRoundedChangeHighlights = false
	var additionalVisualLines: [Int] = []
	{
		didSet
		{
			if oldValue != additionalVisualLines
			{
				invalidateVisualRowGeometry()
			}
		}
	}
	private(set) var visualRowRects: [NSRect] = []
	private(set) var visualLineCounts: [Int] = []
	private(set) var visualGeometryBuildCount = 0
	private var rowStartOffsets: [Int] = []
	private var rowIndex = GitDiffRowIndex(rectangles: [])
	private var visualGeometryKey: VisualGeometryKey?
	private weak var observedTextStorage: NSTextStorage?

	private struct VisualGeometryKey: Equatable
	{
		let container: ObjectIdentifier?
		let manager: ObjectIdentifier?
		let containerSize: NSSize?
		let lineFragmentPadding: CGFloat?
		let origin: NSPoint
		let inset: NSSize
		let width: CGFloat
	}

	private struct VisualRowMeasurements
	{
		let starts: [CGFloat]
		let lineCounts: [Int]
	}

	func invalidateVisualRowGeometry()
	{
		visualGeometryKey = nil
	}

	@objc private func invalidateGeometryAfterTextEditing(_ notification: Notification)
	{
		invalidateVisualRowGeometry()
	}

	private func observeTextStorage()
	{
		guard observedTextStorage !== textStorage
		else
		{
			return
		}
		NotificationCenter.default.removeObserver(
			self,
			name: NSTextStorage.didProcessEditingNotification,
			object: observedTextStorage
		)
		observedTextStorage = textStorage
		if let textStorage
		{
			NotificationCenter.default.addObserver(
				self,
				selector: #selector(invalidateGeometryAfterTextEditing(_:)),
				name: NSTextStorage.didProcessEditingNotification,
				object: textStorage
			)
		}
		invalidateVisualRowGeometry()
	}

	private func currentGeometryKey() -> VisualGeometryKey
	{
		VisualGeometryKey(
			container: textContainer.map(ObjectIdentifier.init),
			manager: layoutManager.map(ObjectIdentifier.init),
			containerSize: textContainer?.containerSize,
			lineFragmentPadding: textContainer?.lineFragmentPadding,
			origin: textContainerOrigin,
			inset: textContainerInset,
			width: bounds.width
		)
	}

	func updateVisualRowRects()
	{
		observeTextStorage()
		guard visualGeometryKey != currentGeometryKey()
		else
		{
			return
		}

		measureVisualRows()
		rowIndex = GitDiffRowIndex(rectangles: visualRowRects)
		visualGeometryKey = currentGeometryKey()
		visualGeometryBuildCount += 1
	}

	private func measureVisualRows()
	{
		guard let layoutManager, let textContainer
		else
		{
			visualLineCounts = Array(
				repeating: 1,
				count: rows.count
			)
			visualRowRects = rows.indices.map
			{
				NSRect(
					x: 0,
					y: CGFloat($0) * GitUnifiedCodeView.lineHeight,
					width: bounds.width,
					height: GitUnifiedCodeView.lineHeight
				)
			}
			return
		}
		layoutManager.ensureLayout(for: textContainer)
		let measurements = measureRowFragments(using: layoutManager)
		visualLineCounts = measurements.lineCounts
		let usedBottom = max(
			layoutManager.usedRect(for: textContainer).maxY,
			layoutManager.extraLineFragmentRect.maxY
		) + textContainerOrigin.y
		visualRowRects = makeVisualRowRectangles(
			from: measurements,
			usedBottom: usedBottom
		)
	}

	private func measureRowFragments(using layoutManager: NSLayoutManager) -> VisualRowMeasurements
	{
		let textLength = (string as NSString).length
		var starts: [CGFloat] = []
		var lineCounts: [Int] = []
		for (index, row) in rows.enumerated()
		{
			let length = (row.text as NSString).length + (index + 1 < rows.count ? 1 : 0)
			let range = NSRange(
				location: rowStartOffsets[index],
				length: length
			)
			guard length > 0, NSMaxRange(range) <= textLength
			else
			{
				let extra = layoutManager.extraLineFragmentRect
				starts.append(max(
					starts.last.map
					{
						$0 + GitUnifiedCodeView.lineHeight
					} ?? 0,
					extra.minY
				))
				lineCounts.append(1)
				continue
			}
			let glyphs = layoutManager.glyphRange(
				forCharacterRange: range,
				actualCharacterRange: nil
			)
			var fragmentStarts: [CGFloat] = []
			var glyphIndex = glyphs.location
			while glyphIndex < NSMaxRange(glyphs)
			{
				var fragment = NSRange()
				let fragmentRect = layoutManager.lineFragmentRect(
					forGlyphAt: glyphIndex,
					effectiveRange: &fragment
				)
				let y = fragmentRect.minY + textContainerOrigin.y
				if fragmentStarts.last != y
				{
					fragmentStarts.append(y)
				}
				glyphIndex = NSMaxRange(fragment)
			}
			starts.append(fragmentStarts.first ?? 0)
			lineCounts.append(max(
				1,
				fragmentStarts.count
			))
		}
		return VisualRowMeasurements(
			starts: starts,
			lineCounts: lineCounts
		)
	}

	private func makeVisualRowRectangles(
		from measurements: VisualRowMeasurements,
		usedBottom: CGFloat
	) -> [NSRect]
	{
		rows.indices.map
		{
			index in
			let top = measurements.starts[index]
			let extra = additionalVisualLines.indices.contains(index)
				? additionalVisualLines[index] : 0
			let expectedBottom = top + CGFloat(measurements.lineCounts[index] + extra)
				* GitUnifiedCodeView.lineHeight
			let bottom = index + 1 < measurements.starts.count
				? max(
					expectedBottom,
					measurements.starts[index + 1]
				)
				: max(
					expectedBottom,
					usedBottom
				)
			return NSRect(
				x: 0,
				y: top,
				width: bounds.width,
				height: bottom - top
			)
		}
	}

	func visualRowIndices(
		from minimumY: CGFloat,
		through maximumY: CGFloat
	) -> Range<Int>
	{
		updateVisualRowRects()
		return rowIndex.candidates(
			from: minimumY,
			through: maximumY
		)
	}

	func visualRowRect(at index: Int) -> NSRect
	{
		if visualRowRects.indices.contains(index)
		{
			return visualRowRects[index]
		}
		return NSRect(
			x: 0,
			y: CGFloat(index) * GitUnifiedCodeView.lineHeight,
			width: bounds.width,
			height: GitUnifiedCodeView.lineHeight
		)
	}

	override func writeSelection(
		to pasteboard: NSPasteboard,
		type: NSPasteboard.PasteboardType
	) -> Bool
	{
		guard type == .string, !placeholderIndices.isEmpty
		else
		{
			return super.writeSelection(
				to: pasteboard,
				type: type
			)
		}
		let selection = selectedRange()
		let sourceText = string as NSString
		let lastSourceRow = rows.indices.last
		{
			!placeholderIndices.contains($0)
		}
		var offset = 0
		var selectedText = ""
		for (index, row) in rows.enumerated()
		{
			let newlineLength = index + 1 < rows.count ? 1 : 0
			let textLength = (row.text as NSString).length
			let separatorLength = index < (lastSourceRow ?? -1) ? newlineLength : 0
			let rowRange = NSRange(
				location: offset,
				length: textLength + separatorLength
			)
			let intersection = NSIntersectionRange(
				selection,
				rowRange
			)
			if !placeholderIndices.contains(index), intersection.length > 0
			{
				selectedText += sourceText.substring(with: intersection)
			}
			offset += textLength + newlineLength
		}
		return pasteboard.setString(
			selectedText,
			forType: .string
		)
	}

	override func drawBackground(in rect: NSRect)
	{
		super.drawBackground(in: rect)
		for index in visualRowIndices(
			from: rect.minY,
			through: rect.maxY
		)
		{
			let row = rows[index]
			let stripe = visualRowRect(at: index)
			guard stripe.intersects(rect)
			else
			{
				continue
			}
			if placeholderIndices.contains(index)
			{
				drawPlaceholder(in: stripe)
				continue
			}
			let color: NSColor? = row.kind == .addition ? .systemGreen
				: row.kind == .deletion ? .systemRed : nil
			guard let color
			else
			{
				continue
			}
			color.withAlphaComponent(0.12).setFill()
			stripe.fill()
			if drawsRoundedChangeHighlights
			{
				drawChangedRanges(
					row,
					at: index,
					color: color
				)
			}
		}
	}

	private func drawChangedRanges(
		_ row: GitDiffRow,
		at index: Int,
		color: NSColor
	)
	{
		guard let layoutManager, let textContainer
		else
		{
			return
		}
		let rowStart = rowStartOffsets[index]
		let rowLength = (row.text as NSString).length
		color.withAlphaComponent(0.24).setFill()
		for span in row.changedRanges where span.length > 0
			&& span.location >= 0 && NSMaxRange(span) <= rowLength
		{
			let characters = NSRange(
				location: rowStart + span.location,
				length: span.length
			)
			guard NSMaxRange(characters) <= (string as NSString).length
			else
			{
				continue
			}
			let glyphs = layoutManager.glyphRange(
				forCharacterRange: characters,
				actualCharacterRange: nil
			)
			var glyphIndex = glyphs.location
			while glyphIndex < NSMaxRange(glyphs)
			{
				var fragment = NSRange()
				_ = layoutManager.lineFragmentRect(
					forGlyphAt: glyphIndex,
					effectiveRange: &fragment
				)
				let segment = NSIntersectionRange(
					glyphs,
					fragment
				)
				guard segment.length > 0
				else
				{
					break
				}
				let segmentRect = layoutManager.boundingRect(
					forGlyphRange: segment,
					in: textContainer
				)
				let highlight = NSRect(
					x: segmentRect.minX + textContainerOrigin.x - 1,
					y: segmentRect.minY + textContainerOrigin.y + 2,
					width: segmentRect.width + 2,
					height: max(
						1,
						segmentRect.height - 4
					)
				)
				NSBezierPath(
					roundedRect: highlight,
					xRadius: 3,
					yRadius: 3
				).fill()
				glyphIndex = NSMaxRange(segment)
			}
		}
	}

	private func drawPlaceholder(in stripe: NSRect)
	{
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		NSBezierPath(rect: stripe).addClip()
		AppKitColorTokens.elevated.setFill()
		stripe.fill()
		NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
		let hatch = NSBezierPath()
		for x in stride(
			from: -stripe.height,
			through: stripe.width,
			by: 7
		)
		{
			hatch.move(to: NSPoint(
				x: x,
				y: stripe.maxY
			))
			hatch.line(to: NSPoint(
				x: x + stripe.height,
				y: stripe.minY
			))
		}
		hatch.lineWidth = 0.5
		hatch.stroke()
	}
}
