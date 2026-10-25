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
			let document = DiffScrollDocumentView(frame: NSRect(
				x: 0,
				y: 0,
				width: 900,
				height: 2_000
			))
			outer.documentView = document
			code.translatesAutoresizingMaskIntoConstraints = false
			document.addSubview(code)
			NSLayoutConstraint.activate([
				code.leadingAnchor.constraint(equalTo: document.leadingAnchor),
				code.trailingAnchor.constraint(equalTo: document.trailingAnchor),
				code.topAnchor.constraint(equalTo: document.topAnchor),
			])
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
			window.prepareForTesting()
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
				inner.scrollWheel(with: try wheel(
					x: 0,
					y: 0,
					phase: .began,
					in: inner
				))
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
				let verticalEnd = try wheel(
					x: 0,
					y: 0,
					phase: .ended,
					in: inner
				)
				inner.scrollWheel(with: verticalEnd)
				#expect(outer.events.last === verticalEnd)
				if !wraps
				{
					try #require(inner.hasHorizontalScroller)
					try #require(source.frame.maxX > inner.contentView.bounds.maxX)
					let forwardedCount = outer.events.count
					let clip = inner.contentView
					let horizontal = clip.bounds.origin.x
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
					inner.scrollWheel(with: try wheel(
						x: 0,
						y: 0,
						phase: .began,
						in: inner
					))
					let horizontalEvent = try wheel(
						x: -40,
						y: 0,
						in: inner
					)
					native.mark("horizontal.dispatch.begin")
					inner.scrollWheel(with: horizontalEvent)
					inner.scrollWheel(with: try wheel(
						x: 0,
						y: 0,
						phase: .ended,
						in: inner
					))
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
					// Shift stays with the code pane. This synthetic event checks routing;
					// native Shift-axis normalization is outside this synthetic fixture.
					inner.scrollWheel(with: try wheel(
						x: 0,
						y: 0,
						phase: .began,
						flags: .maskShift,
						in: inner
					))
					let shiftedEvent = try wheel(
						x: 0,
						y: -40,
						flags: .maskShift,
						in: inner
					)
					inner.scrollWheel(with: shiftedEvent)
					inner.scrollWheel(with: try wheel(
						x: 0,
						y: 0,
						phase: .ended,
						flags: .maskShift,
						in: inner
					))
					#expect(outer.events.count == forwardedCount)
					#expect(source.selectedRange() == selection)
				}
			}
		}
	}

	private func wheel(
		x: Int32,
		y: Int32,
		phase: WheelPhase = .changed,
		flags: CGEventFlags = [],
		in scroll: NSScrollView
	) throws -> NSEvent
	{
		// Keep physical keyboard state out of the requested synthetic wheel gesture.
		let eventSource = try #require(CGEventSource(stateID: .privateState))
		let event = try #require(CGEvent(
			scrollWheelEvent2Source: eventSource,
			units: .pixel,
			wheelCount: 2,
			wheel1: y,
			wheel2: x,
			wheel3: 0
		))
		event.flags = flags
		// Keep each trackpad gesture's native phase, including its zero-delta boundaries.
		event.setIntegerValueField(
			.scrollWheelEventIsContinuous,
			value: 1
		)
		event.setIntegerValueField(
			.scrollWheelEventScrollPhase,
			value: phase.rawValue
		)
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
		let screenPoint = window.convertPoint(toScreen: point)
		// CGEvent uses a top-left screen origin; AppKit screen coordinates use bottom-left.
		event.location = CGPoint(
			x: screenPoint.x,
			y: CGDisplayBounds(CGMainDisplayID()).height - screenPoint.y
		)
		let located = try #require(NSEvent(cgEvent: event))
		try #require(located.type == .scrollWheel)
		try #require(located.hasPreciseScrollingDeltas)
		try #require(located.phase == phase.nativePhase)
		try #require(located.modifierFlags.contains(.shift) == flags.contains(.maskShift))
		if flags.isEmpty
		{
			try #require(located.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty)
			try #require(located.scrollingDeltaX == CGFloat(x))
			try #require(located.scrollingDeltaY == CGFloat(y))
		}
		let timing = TestTiming.begin(
			"native.wheel",
			detail: "delta=\(x),\(y) bounds=\(scroll.bounds) visible=\(viewport) " +
				"windowPoint=\(point) screenPoint=\(screenPoint) " +
				"nativeLocation=\(located.locationInWindow) nativeWindow=\(located.windowNumber)"
		)
		defer
		{
			timing.end()
		}
		// Preserve the real native event backing used by NSScrollView, not only its accessors.
		return located
	}

	// Core Graphics and NSEvent use different raw values for changed and ended phases.
	private enum WheelPhase: Int64
	{
		case began = 1, changed = 2, ended = 4

		var nativePhase: NSEvent.Phase
		{
			switch self
			{
			case .began: .began
			case .changed: .changed
			case .ended: .ended
			}
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}

	private final class DiffScrollDocumentView: NSView
	{
		override var isFlipped: Bool
		{
			true
		}
	}

	private final class RecordingScrollView: NSScrollView
	{
		var events: [NSEvent] = []

		override func scrollWheel(with event: NSEvent)
		{
			events.append(event)
			super.scrollWheel(with: event)
		}
	}
}
