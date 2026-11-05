import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct GitDiffLineSelectionTests
{
	@Test func selectedLineSurvivesSwitchingBetweenUnifiedAndSplit() throws
	{
		let rows = [
			GitDiffRow(
				id: "old",
				kind: .deletion,
				text: "old",
				oldLine: 1,
				newLine: nil
			),
			GitDiffRow(
				id: "new",
				kind: .addition,
				text: "new",
				oldLine: nil,
				newLine: 1
			)
		]
		let diff = GitAdaptiveDiffView(
			rows: rows,
			path: "test.swift"
		)
		diff.layoutPreference = .unified
		func descendants(_ view: NSView) -> [NSView]
		{
			[view] + view.subviews.flatMap(descendants)
		}
		let rulers = descendants(diff)
			.compactMap
			{
				($0 as? NSScrollView)?.verticalRulerView as? GitDiffLineRuler
			}
		let ruler = try #require(rulers.first)
		ruler.onSelectLine?("old")
		let unified = try #require(descendants(diff).compactMap
		{
			$0 as? GitDiffTextView
		}.first)
		#expect(unified.selectedLineID == "old")
		let paragraph = try #require(unified.textStorage?.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		#expect(paragraph.minimumLineHeight == TypographyConfiguration.current.codeSize * 1.8)
		#expect(paragraph.maximumLineHeight == paragraph.minimumLineHeight)
		diff.layoutPreference = .split
		let splitSources = descendants(diff).compactMap
		{
			$0 as? GitDiffTextView
		}
		#expect(splitSources.count == 2)
		#expect(splitSources.allSatisfy
		{
			$0.selectedLineID == "old"
		})
		diff.layoutPreference = .unified
		#expect(unified.selectedLineID == "old")
	}

	@Test func gutterReleaseSelectsRowAndPreservesTextSelection() throws
	{
		let rows = [
			GitDiffRow(
				id: "deleted",
				kind: .deletion,
				text: "old",
				oldLine: 1,
				newLine: nil
			),
			GitDiffRow(
				id: "added",
				kind: .addition,
				text: "new",
				oldLine: nil,
				newLine: 1
			)
		]
		let code = GitUnifiedCodeView(
			rows: rows,
			path: "test.swift"
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 180
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = code
		window.layoutIfNeeded()
		code.layoutSubtreeIfNeeded()
		defer
		{
			window.close()
		}
		func find<T: NSView>(
			_ view: NSView,
			_: T.Type
		) -> T?
		{
			if let target = view as? T
			{
				return target
			}
			for child in view.subviews
			{
				if let result = find(
					child,
					T.self
				)
				{
					return result
				}
			}
			return nil
		}
		let scroll = try #require(find(
			code,
			NSScrollView.self
		))
		let ruler = try #require(scroll.verticalRulerView as? GitDiffLineRuler)
		let source = try #require(scroll.documentView as? GitDiffTextView)
		source.updateVisualRowRects()
		source.setSelectedRange(NSRange(
			location: 1,
			length: 1
		))
		var selected: String?
		ruler.onSelectLine =
		{
			selected = $0
		}
		let sourcePoint = NSPoint(
			x: 0,
			y: source.visualRowRect(at: 0).midY
		)
		let rulerPoint = ruler.convert(
			sourcePoint,
			from: source
		)
		let windowPoint = ruler.convert(
			NSPoint(
				x: ruler.bounds.midX,
				y: rulerPoint.y
			),
			to: nil
		)
		func event(_ type: NSEvent.EventType) throws -> NSEvent
		{
			try #require(NSEvent.mouseEvent(
				with: type,
				location: windowPoint,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			))
		}
		ruler.mouseDown(with: try event(.leftMouseDown))
		#expect(selected == nil)
		ruler.mouseUp(with: try event(.leftMouseUp))
		#expect(selected == "deleted")
		#expect(source.selectedRange() == NSRange(
			location: 1,
			length: 1
		))
	}
}
