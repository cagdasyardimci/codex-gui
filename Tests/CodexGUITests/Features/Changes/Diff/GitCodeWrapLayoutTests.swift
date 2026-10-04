import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitCodeWrapLayoutTests
{
	@Test func hardSeparatorsKeepMeasuredRowsAndFiniteHeightWithWrappingOff()
	{
		for separator in ["\u{2028}", "\u{2029}", "\r"]
		{
			let rows = [
				GitDiffRow(
					id: "changed",
					kind: .deletion,
					text: "old\(separator)line",
					oldLine: 1,
					newLine: nil
				),
				GitDiffRow(
					id: "following",
					kind: .context,
					text: "after",
					oldLine: 2,
					newLine: 1
				),
			]
			let code = GitUnifiedCodeView(
				rows: rows,
				path: "Example.swift"
			)
			let window = host(
				code,
				width: 240
			)
			defer
			{
				window.close()
			}
			settle(window)
			#expect(code.visualLineCounts == [2, 1])
			#expect(code.visualRowRects[1].minY == 2 * GitUnifiedCodeView.lineHeight)
			#expect(code.visualRowRects[0].maxY == code.visualRowRects[1].minY)
			#expect(code.naturalContentHeight >= 3 * GitUnifiedCodeView.lineHeight + 16)
			let source = descendants(code).compactMap
			{
				$0 as? NSTextView
			}.first
			#expect(source?.string == rows.map(\.text).joined(separator: "\n"))
			#expect(source?.frame.height.isFinite == true)
			#expect((source?.frame.height ?? 0) >= code.visualRowRects[1].maxY)
			#expect(source?.textContainer?.containerSize.height.isFinite == true)
			code.wrapsCode = true
			settle(window)
			code.wrapsCode = false
			settle(window)
			#expect(code.visualRowRects[1].minY == 2 * GitUnifiedCodeView.lineHeight)
			#expect(code.hasHorizontalScroller)
		}
	}

	@Test func splitHardSeparatorAlignsFollowingRowsAndPlaceholderWithoutWrapping()
	{
		let rows = [
			GitDiffRow(
				id: "old-hard-break",
				kind: .deletion,
				text: "old\u{2028}line",
				oldLine: 1,
				newLine: nil
			),
			GitDiffRow(
				id: "old-only",
				kind: .deletion,
				text: "old only",
				oldLine: 2,
				newLine: nil
			),
			GitDiffRow(
				id: "new",
				kind: .addition,
				text: "new",
				oldLine: nil,
				newLine: 1
			),
			GitDiffRow(
				id: "following",
				kind: .context,
				text: "after",
				oldLine: 3,
				newLine: 2
			),
			GitDiffRow(
				id: "final-old",
				kind: .deletion,
				text: "tail\u{2028}line",
				oldLine: 4,
				newLine: nil
			),
		]
		let diff = GitAdaptiveDiffView(
			rows: rows,
			path: "Example.swift"
		)
		let window = host(
			diff,
			width: 900
		)
		defer
		{
			window.close()
		}
		diff.layoutPreference = .split
		settle(window)
		let columns = descendants(diff).compactMap
		{
			$0 as? GitUnifiedCodeView
		}
		#expect(columns.count == 2)
		if columns.count == 2
		{
			let old = columns[0]
			let new = columns[1]
			#expect(old.visualLineCounts == [2, 1, 1, 2])
			#expect(new.visualLineCounts == [1, 1, 1, 1])
			#expect(abs(old.visualRowRects[1].minY - new.visualRowRects[1].minY) <= 1)
			#expect(abs(old.visualRowRects[2].minY - new.visualRowRects[2].minY) <= 1)
			#expect(abs(old.visualRowRects.last!.maxY - new.visualRowRects.last!.maxY) <= 1)
			#expect(old.hasHorizontalScroller && new.hasHorizontalScroller)
			diff.wrapsCode = true
			settle(window)
			diff.wrapsCode = false
			settle(window)
			#expect(abs(old.visualRowRects[1].minY - new.visualRowRects[1].minY) <= 1)
			#expect(abs(old.visualRowRects.last!.maxY - new.visualRowRects.last!.maxY) <= 1)
		}
	}

	@Test func unifiedWrapReflowsRowsAndRestoresHorizontalScrolling()
	{
		let long = String(
			repeating: "wide source ",
			count: 24
		)
		let rows = [
			GitDiffRow(
				id: "change",
				kind: .deletion,
				text: long,
				oldLine: 1,
				newLine: nil
			),
			GitDiffRow(
				id: "context",
				kind: .context,
				text: "tail",
				oldLine: 2,
				newLine: 1
			),
		]
		let code = GitUnifiedCodeView(
			rows: rows,
			path: "Example.swift"
		)
		let window = host(
			code,
			width: 240
		)
		defer
		{
			window.close()
		}
		code.wrapsCode = true
		settle(window)
		#expect(code.naturalContentHeight > GitUnifiedCodeView.contentHeight(rowCount: 2))
		#expect(code.visualLineCounts[0] > 1)
		#expect(code.visualRowRects[1].minY >= code.visualRowRects[0].maxY)
		#expect(!code.hasHorizontalScroller)
		let narrowLineCount = code.visualLineCounts[0]
		let narrowHeight = code.naturalContentHeight
		window.setContentSize(NSSize(
			width: 640,
			height: 600
		))
		settle(window)
		#expect(code.visualLineCounts[0] < narrowLineCount)
		#expect(code.naturalContentHeight < narrowHeight)
		code.wrapsCode = false
		settle(window)
		#expect(code.naturalContentHeight == GitUnifiedCodeView.contentHeight(rowCount: 2))
		#expect(code.visualRowRects[1].minY == GitUnifiedCodeView.lineHeight)
		#expect(code.hasHorizontalScroller)
		let source = descendants(code).compactMap
		{
			$0 as? NSTextView
		}.first
		#expect(source?.string == rows.map(\.text).joined(separator: "\n"))
	}

	@Test func splitWrapAlignsRowsAfterAsymmetricChangeAndFinalPlaceholder()
	{
		let long = String(
			repeating: "old source ",
			count: 30
		)
		let rows = [
			GitDiffRow(
				id: "old",
				kind: .deletion,
				text: long,
				oldLine: 1,
				newLine: nil
			),
			GitDiffRow(
				id: "new",
				kind: .addition,
				text: "short",
				oldLine: nil,
				newLine: 1
			),
			GitDiffRow(
				id: "next",
				kind: .context,
				text: "next line",
				oldLine: 2,
				newLine: 2
			),
			GitDiffRow(
				id: "final",
				kind: .deletion,
				text: long,
				oldLine: 3,
				newLine: nil
			),
		]
		let diff = GitAdaptiveDiffView(
			rows: rows,
			path: "Example.swift"
		)
		let window = host(
			diff,
			width: 900
		)
		defer
		{
			window.close()
		}
		diff.layoutPreference = .split
		diff.wrapsCode = true
		settle(window)
		let columns = descendants(diff).compactMap
		{
			$0 as? GitUnifiedCodeView
		}
		#expect(columns.count == 2)
		if columns.count == 2
		{
			let old = columns[0]
			let new = columns[1]
			#expect(old.visualLineCounts[0] > new.visualLineCounts[0])
			#expect(abs(old.visualRowRects[1].minY - new.visualRowRects[1].minY) <= 1)
			#expect(abs(old.visualRowRects.last!.maxY - new.visualRowRects.last!.maxY) <= 1)
			#expect(!old.hasHorizontalScroller && !new.hasHorizontalScroller)
		}
	}

	@Test func wrappedGlyphsStayInsideVisibleColumnsAfterResize() throws
	{
		let rows = [
			GitDiffRow(
				id: "long",
				kind: .context,
				text: "\tpython3 scripts/run-swift-tests.py -- swift test $(TEST_FLAGS) "
					+ String(
						repeating: "WindowLayoutTests|",
						count: 20
					),
				oldLine: 30,
				newLine: 29
			),
		]
		for preference in [GitDiffLayoutPreference.unified, .split]
		{
			let diff = GitAdaptiveDiffView(
				rows: rows,
				path: "Makefile"
			)
			diff.layoutPreference = preference
			diff.wrapsCode = true
			let window = host(
				diff,
				width: 900
			)
			defer
			{
				window.close()
			}
			for width in [CGFloat(900), 560, 1100]
			{
				window.setContentSize(NSSize(
					width: width,
					height: 600
				))
				settle(window)
				for source in descendants(diff).compactMap(
					{
						$0 as? GitDiffTextView
					}
				)
				{
					let scroll = try #require(source.enclosingScrollView)
					let manager = try #require(source.layoutManager)
					let container = try #require(source.textContainer)
					let visible = source.convert(
						scroll.contentView.bounds,
						from: scroll.contentView
					)
					#expect(source.frame.maxX <= visible.maxX + 0.5)
					#expect(!scroll.hasHorizontalScroller)
					#expect(source.string == rows[0].text)
					manager
						.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container))
						{
							_, used, _, _, _ in
							#expect(used.maxX + source.textContainerOrigin.x <= visible.maxX + 0.5)
						}
				}
			}
		}
	}

	private func host(
		_ content: NSView,
		width: CGFloat
	) -> NSWindow
	{
		_ = NSApplication.shared
		let controller = NSViewController()
		let root = NSView()
		controller.view = root
		root.addSubview(content)
		content.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
			content.topAnchor.constraint(equalTo: root.topAnchor),
		])
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: width,
				height: 600
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		return window
	}

	private func settle(_ window: NSWindow)
	{
		for _ in 0 ..< 5
		{
			window.layoutIfNeeded()
			window.contentView?.layoutSubtreeIfNeeded()
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}
