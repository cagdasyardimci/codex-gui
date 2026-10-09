import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffScrollingTests
{
	@Test(
		arguments: [GitDiffLayoutPreference.unified, .split],
		[false, true]
	)
	func verticalWheelReachesOuterViewerAndHorizontalWheelStaysInCode(
		layout: GitDiffLayoutPreference,
		wraps: Bool
	) async throws
	{
		_ = NSApplication.shared
		let rows = (1 ... 60).map
		{
			GitDiffRow(
				id: String($0),
				kind: .context,
				text: String(
					repeating: "wide source ",
					count: 30
				),
				oldLine: $0,
				newLine: $0
			)
		}
		let code = GitAdaptiveDiffView(
			rows: rows,
			path: "Example.swift"
		)
		code.layoutPreference = layout
		code.wrapsCode = wraps
		let outer = RecordingScrollView()
		let document = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 900,
			height: 2_000
		))
		outer.documentView = document
		AppKitLayout.pin(
			code,
			to: document,
			inset: 0
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 240
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = outer
		defer
		{
			window.close()
		}
		for _ in 0 ..< 4
		{
			outer.layoutSubtreeIfNeeded()
		}
		let sources = descendants(code).compactMap
		{
			$0 as? GitDiffTextView
		}
		#expect(sources.count == (layout == .split ? 2 : 1))
		for source in sources
		{
			let inner = try #require(source.enclosingScrollView)
			#expect(try #require(outer.documentView).frame.height > outer.contentSize.height)
			source.setSelectedRange(NSRange(
				location: 2,
				length: 5
			))
			let selection = source.selectedRange()
			let horizontal = inner.contentView.bounds.origin.x
			let verticalEvent = try wheel(
				x: 0,
				y: -40
			)
			inner.scrollWheel(with: verticalEvent)
			#expect(outer.events.last === verticalEvent)
			#expect(inner.contentView.bounds.origin.x == horizontal)
			#expect(source.selectedRange() == selection)
			if !wraps
			{
				let forwardedCount = outer.events.count
				inner.scrollWheel(with: try wheel(
					x: -40,
					y: 0
				))
				try await Task.sleep(for: .milliseconds(50))
				#expect(inner.contentView.bounds.origin.x > horizontal)
				#expect(outer.events.count == forwardedCount)
			}
		}
	}

	private func wheel(
		x: Int32,
		y: Int32
	) throws -> NSEvent
	{
		let event = try #require(CGEvent(
			scrollWheelEvent2Source: nil,
			units: .pixel,
			wheelCount: 2,
			wheel1: y,
			wheel2: x,
			wheel3: 0
		))
		return try #require(NSEvent(cgEvent: event))
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private final class RecordingScrollView: NSScrollView
	{
		var events: [NSEvent] = []

		override func scrollWheel(with event: NSEvent)
		{
			events.append(event)
		}
	}
}
