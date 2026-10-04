import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffGeometryCacheTests
{
	@Test func unchangedLayoutAndDirtyQueriesReuseMeasuredRows() throws
	{
		let code = GitUnifiedCodeView(
			rows: rows(count: 300),
			path: "Example.swift"
		)
		let window = host(
			code,
			width: 400
		)
		defer
		{
			window.close()
		}
		settle(window)
		let source = try self.source(in: code)
		source.updateVisualRowRects()
		let builds = source.visualGeometryBuildCount
		let rectangles = source.visualRowRects
		for _ in 0 ..< 5
		{
			code.needsLayout = true
			settle(window)
			source.updateVisualRowRects()
			let visible = source.visualRowIndices(
				from: rectangles[100].minY + 1,
				through: rectangles[103].maxY - 1
			)
			#expect(visible == 100 ..< 104)
		}
		#expect(source.visualGeometryBuildCount == builds)
		#expect(source.visualRowRects == rectangles)
	}

	@Test func textAttributesContainerWidthAndInsetsInvalidateGeometry() throws
	{
		let code = GitUnifiedCodeView(
			rows: rows(count: 3),
			path: "Example.swift"
		)
		let window = host(
			code,
			width: 400
		)
		defer
		{
			window.close()
		}
		settle(window)
		let source = try self.source(in: code)
		source.updateVisualRowRects()
		var builds = source.visualGeometryBuildCount
		let storage = try #require(source.textStorage)
		storage.addAttribute(
			.font,
			value: NSFont.monospacedSystemFont(
				ofSize: 16,
				weight: .regular
			),
			range: NSRange(
				location: 0,
				length: storage.length
			)
		)
		source.updateVisualRowRects()
		#expect(source.visualGeometryBuildCount == builds + 1)
		builds = source.visualGeometryBuildCount
		let container = try #require(source.textContainer)
		container.containerSize.width += 30
		source.updateVisualRowRects()
		#expect(source.visualGeometryBuildCount == builds + 1)
		builds = source.visualGeometryBuildCount
		source.textContainerInset.height = 4
		source.updateVisualRowRects()
		#expect(source.visualGeometryBuildCount == builds + 1)
		#expect(source.visualRowRects[0].minY >= 4)
	}

	@Test func wrappingAndSplitPaddingRebuildGeometryWhileKeepingSelection() throws
	{
		let long = String(
			repeating: "long source ",
			count: 30
		)
		var content = rows(count: 2)
		content[0] = GitDiffRow(
			id: "long",
			kind: .context,
			text: long,
			oldLine: 1,
			newLine: 1
		)
		let code = GitUnifiedCodeView(
			rows: content,
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
		let source = try self.source(in: code)
		source.updateVisualRowRects()
		let builds = source.visualGeometryBuildCount
		let selection = NSRange(
			location: 5,
			length: 6
		)
		source.setSelectedRange(selection)
		code.wrapsCode = true
		settle(window)
		#expect(source.visualGeometryBuildCount > builds)
		#expect(source.visualLineCounts[0] > 1)
		#expect(source.selectedRange() == selection)
		code.wrapsCode = false
		settle(window)
		let unpadded = source.visualRowRects[0].height
		let beforePadding = source.visualGeometryBuildCount
		code.setAdditionalVisualLines([2, 0])
		settle(window)
		#expect(source.visualGeometryBuildCount > beforePadding)
		#expect(source.visualRowRects[0].height >= unpadded + 2 * GitUnifiedCodeView.lineHeight)
		#expect(source.selectedRange() == selection)
	}

	private func rows(count: Int) -> [GitDiffRow]
	{
		(0 ..< count).map
		{
			GitDiffRow(
				id: String($0),
				kind: .context,
				text: "row \($0)",
				oldLine: $0,
				newLine: $0
			)
		}
	}

	private func source(in code: NSView) throws -> GitDiffTextView
	{
		try #require(descendants(code).compactMap
		{
			$0 as? GitDiffTextView
		}.first)
	}

	private func host(
		_ content: NSView,
		width: CGFloat
	) -> NSWindow
	{
		_ = NSApplication.shared
		let root = NSView()
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
		window.contentView = root
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
