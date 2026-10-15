import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitDiffScrollingTests
{
	// Reserve native input handling while each wheel scenario settles asynchronously.
	@Test(
		.serialized,
		.timeLimit(.minutes(1)),
		arguments: [GitDiffLayoutPreference.unified, .split],
		[false, true]
	)
	func verticalWheelReachesOuterViewerAndHorizontalWheelStaysInCode(
		layout: GitDiffLayoutPreference,
		wraps: Bool
	) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let native = TestTiming.begin(
				"native.body",
				detail: "layout=\(layout.rawValue) wraps=\(wraps)"
			)
			defer
			{
				native.end()
			}
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
			// Exercise native scrolling in a presented window, after AppKit installs its viewport.
			// Hidden-window scroll animation is not a reliable completion checkpoint.
			window.orderFront(nil)
			window.displayIfNeeded()
			defer
			{
				window.close()
			}
			for _ in 0 ..< 4
			{
				outer.layoutSubtreeIfNeeded()
			}
			native.mark("fixture.ready")
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
					y: -40,
					in: inner
				)
				native.mark("vertical.dispatch.begin")
				inner.scrollWheel(with: verticalEvent)
				native.mark("vertical.dispatch.end")
				#expect(outer.events.last === verticalEvent)
				#expect(inner.contentView.bounds.origin.x == horizontal)
				#expect(source.selectedRange() == selection)
				if !wraps
				{
					try #require(inner.hasHorizontalScroller)
					try #require(source.frame.maxX > inner.contentView.bounds.maxX)
					let forwardedCount = outer.events.count
					let clip = inner.contentView
					let previousPostsBoundsChanges = clip.postsBoundsChangedNotifications
					clip.postsBoundsChangedNotifications = true
					let (movements, continuation) = AsyncStream<Void>.makeStream()
					let observer = NotificationCenter.default.addObserver(
						forName: NSView.boundsDidChangeNotification,
						object: clip,
						queue: nil
					)
					{
						_ in
						MainActor.assumeIsolated
						{
							native.mark("horizontal.boundsChanged")
							guard clip.bounds.origin.x > horizontal
							else
							{
								return
							}
							native.mark("horizontal.moved")
							continuation.yield(())
							continuation.finish()
						}
					}
					defer
					{
						NotificationCenter.default.removeObserver(observer)
						continuation.finish()
						clip.postsBoundsChangedNotifications = previousPostsBoundsChanges
					}
					let horizontalEvent = try wheel(
						x: -40,
						y: 0,
						in: inner
					)
					native.mark("horizontal.dispatch.begin")
					inner.scrollWheel(with: horizontalEvent)
					native.mark("horizontal.dispatch.end")
					#expect(outer.events.count == forwardedCount)
					// Observe this fixture's native movement instead of assuming AppKit's
					// scroll animation runs before an arbitrary actor scheduling deadline.
					if clip.bounds.origin.x <= horizontal
					{
						native.mark("horizontal.wait.begin")
						var iterator = movements.makeAsyncIterator()
						_ = await iterator.next()
						native.mark("horizontal.wait.end")
					}
					#expect(inner.contentView.bounds.origin.x > horizontal)
					#expect(outer.events.count == forwardedCount)
				}
			}
		}
	}

	private func wheel(
		x: Int32,
		y: Int32,
		in scroll: NSScrollView
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
		let window = try #require(scroll.window)
		// The inner code scroll view spans the full document height, while the outer
		// viewer clips it. A bounds midpoint can be outside the presented window.
		let viewport = scroll.visibleRect.intersection(scroll.bounds)
		try #require(viewport.width > 0 && viewport.height > 0)
		let point = scroll.convert(
			NSPoint(
				x: viewport.midX,
				y: viewport.midY
			),
			to: nil
		)
		let content = try #require(window.contentView)
		let contentPoint = content.convert(
			point,
			from: nil
		)
		try #require(content.bounds.contains(contentPoint))
		let boundsPoint = scroll.convert(
			NSPoint(
				x: scroll.bounds.midX,
				y: scroll.bounds.midY
			),
			to: nil
		)
		let timing = TestTiming.begin(
			"native.wheel",
			detail: "delta=\(x),\(y) bounds=\(scroll.bounds) visible=\(viewport) " +
				"oldWindowPoint=\(boundsPoint) newWindowPoint=\(point) " +
				"contentBounds=\(content.bounds) contentVisible=\(content.visibleRect) " +
				"oldInside=\(content.bounds.contains(content.convert(boundsPoint, from: nil))) " +
				"newContentPoint=\(contentPoint)"
		)
		defer
		{
			timing.end()
		}
		return LocatedWheelEvent(
			base: try #require(NSEvent(cgEvent: event)),
			window: window,
			point: point
		)
	}

	// Keep the CG wheel's real deltas and precision, while attaching the owning viewport.
	private final class LocatedWheelEvent: NSEvent
	{
		let base: NSEvent
		// Recorded events must not retain the window that owns their recording scroll view.
		weak var targetWindow: NSWindow?
		let point: NSPoint

		init(
			base: NSEvent,
			window: NSWindow,
			point: NSPoint
		)
		{
			self.base = base
			targetWindow = window
			self.point = point
			super.init()
		}

		@available(
			*,
			unavailable
		)
		required init?(coder: NSCoder)
		{
			fatalError("init(coder:) has not been implemented")
		}

		override var type: NSEvent.EventType
		{
			.scrollWheel
		}
		override var window: NSWindow?
		{
			targetWindow
		}
		override var windowNumber: Int
		{
			targetWindow?.windowNumber ?? base.windowNumber
		}
		override var locationInWindow: NSPoint
		{
			point
		}
		override var deltaX: CGFloat
		{
			base.deltaX
		}
		override var deltaY: CGFloat
		{
			base.deltaY
		}
		override var scrollingDeltaX: CGFloat
		{
			base.scrollingDeltaX
		}
		override var scrollingDeltaY: CGFloat
		{
			base.scrollingDeltaY
		}
		override var hasPreciseScrollingDeltas: Bool
		{
			base.hasPreciseScrollingDeltas
		}
		override var phase: NSEvent.Phase
		{
			base.phase
		}
		override var momentumPhase: NSEvent.Phase
		{
			base.momentumPhase
		}
		override var timestamp: TimeInterval
		{
			base.timestamp
		}
		override var modifierFlags: NSEvent.ModifierFlags
		{
			base.modifierFlags
		}
		override var isDirectionInvertedFromDevice: Bool
		{
			base.isDirectionInvertedFromDevice
		}
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
