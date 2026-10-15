import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct EffortSliderHoverTests
{
	@Test func bareTrackDoesNotHoverAndPointerScopeFollowsValueChanges() throws
	{
		let fixture = Fixture()
		defer
		{
			fixture.close()
		}
		let slider = fixture.slider
		slider.shouldReduceMotion =
		{
			true
		}
		let cell = try #require(slider.cell as? EffortSliderCell)
		let knob = cell.knobRect(flipped: slider.isFlipped)
		let trackPoint = NSPoint(
			x: 5,
			y: knob.midY
		)
		let knobPoint = NSPoint(
			x: knob.midX,
			y: knob.midY
		)
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider,
			point: trackPoint
		))
		#expect(slider.visualKnobDiameter == 28)
		#expect(!slider.isAnimatingThumbHover)
		slider.mouseMoved(with: try event(
			.mouseMoved,
			slider: slider,
			point: knobPoint
		))
		#expect(slider.visualKnobDiameter == 32)
		slider.mouseMoved(with: try event(
			.mouseMoved,
			slider: slider,
			point: trackPoint
		))
		#expect(slider.visualKnobDiameter == 28)
		slider.mouseMoved(with: try event(
			.mouseMoved,
			slider: slider,
			point: knobPoint
		))
		slider.doubleValue = 0
		#expect(slider.visualKnobDiameter == 28)
		slider.doubleValue = 2
		#expect(slider.visualKnobDiameter == 32)
		slider.isEnabled = false
		#expect(slider.visualKnobDiameter == 28)
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider,
			point: knobPoint
		))
		#expect(slider.visualKnobDiameter == 28)
	}

	@Test func reducedMotionHoverChangesPaintingWithoutChangingCellGeometry() throws
	{
		let fixture = Fixture()
		defer
		{
			fixture.close()
		}
		let slider = fixture.slider
		slider.shouldReduceMotion =
		{
			true
		}
		let cell = try #require(slider.cell as? EffortSliderCell)
		let logical = cell.knobRect(flipped: slider.isFlipped)
		let ticks = (0 ..< slider.numberOfTickMarks).map
		{
			cell.rectOfTickMark(at: $0)
		}
		let value = slider.doubleValue
		let frame = slider.frame
		#expect(fixture.window.makeFirstResponder(slider))
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		#expect(slider.visualKnobRect.width == 32)
		#expect(slider.visualKnobRect.midX == logical.midX)
		#expect(slider.visualKnobRect.midY == logical.midY)
		#expect(cell.knobRect(flipped: slider.isFlipped) == logical)
		#expect((0 ..< slider.numberOfTickMarks).map
		{
			cell.rectOfTickMark(at: $0)
		} == ticks)
		#expect(slider.doubleValue == value)
		#expect(slider.frame == frame)
		#expect(fixture.window.firstResponder === slider)
		#expect(!slider.isAnimatingThumbHover)
		let root = try #require(slider.layer?.sublayers?.first)
		let filled = try #require(root.sublayers?.first)
		let mask = try #require(filled.mask as? CAShapeLayer)
		let path = try #require(mask.path)
		let center = CGPoint(
			x: logical.midX - filled.frame.minX,
			y: logical.midY - filled.frame.minY
		)
		#expect(!path.contains(
			CGPoint(
				x: center.x - 15,
				y: center.y
			),
			using: .evenOdd
		))
		#expect(path.contains(
			CGPoint(
				x: center.x - 17,
				y: center.y
			),
			using: .evenOdd
		))
		let thumb = try #require(slider.layer?.sublayers?.last)
		#expect(thumb.bounds.width == 32)
		#expect(thumb.shadowRadius == 1)
		#expect(!slider.layer!.masksToBounds)
		fixture.window.appearance = NSAppearance(named: .darkAqua)
		#expect(slider.visualKnobRect.width == 32)
		#expect(fixture.window.firstResponder === slider)
		slider.mouseExited(with: try event(
			.mouseExited,
			slider: slider
		))
		#expect(slider.visualKnobRect.width == 28)
		#expect(slider.doubleValue == value)
	}

	@Test func hoverTransitionInterpolatesRetargetsAndStopsOnHiding() throws
	{
		let fixture = Fixture()
		defer
		{
			fixture.close()
		}
		let slider = fixture.slider
		var animations: [ControlledHoverAnimation] = []
		slider.makeHoverAnimation =
		{
			let animation = ControlledHoverAnimation(expanding: $0)
			animations.append(animation)
			return animation
		}
		slider.shouldReduceMotion =
		{
			false
		}
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		#expect(slider.isAnimatingThumbHover)
		// Advance a known frame rather than requiring the main run loop to meet a deadline.
		try #require(animations.last).advance(to: 0.1 / 0.35)
		#expect(slider.visualKnobDiameter > 28)
		#expect(slider.visualKnobDiameter < 32)
		try #require(animations.last).advance(to: 1)
		#expect(abs(slider.visualKnobDiameter - 32) < 0.01)
		#expect(!slider.isAnimatingThumbHover)
		slider.mouseExited(with: try event(
			.mouseExited,
			slider: slider
		))
		try #require(animations.last).advance(to: 0.1 / 0.45)
		let shrinking = slider.visualKnobDiameter
		#expect(shrinking > 28 && shrinking < 32)
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		#expect(abs(slider.visualKnobDiameter - shrinking) < 0.01)
		slider.isHidden = true
		#expect(slider.visualKnobDiameter == 28)
		#expect(!slider.isAnimatingThumbHover)
		// Cancelled drivers cannot repaint after hiding, even if more frames are offered.
		for animation in animations
		{
			animation.advance(to: 1)
		}
		#expect(slider.visualKnobDiameter == 28)
		#expect(slider.doubleValue == 2)
	}

	@Test(.timeLimit(.minutes(1)))
	func defaultHoverDriverDeliversNativeProgressAndCompletesBothTransitions() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let fixture = Fixture()
			defer
			{
				fixture.close()
			}
			let slider = fixture.slider
			slider.shouldReduceMotion =
			{
				false
			}
			let defaultFactory = slider.makeHoverAnimation
			for expanding in [true, false]
			{
				let (events, continuation) = AsyncStream<NativeHoverAnimationEvent>.makeStream()
				let observer = NativeHoverAnimationObserver(continuation: continuation)
				var native: EffortThumbHoverAnimation?
				// Observe the production factory's driver without replacing its native scheduling.
				slider.makeHoverAnimation =
				{
					expanding in
					let driver = defaultFactory(expanding)
					if let animation = driver as? EffortThumbHoverAnimation
					{
						animation.addProgressMark(0.5)
						animation.delegate = observer
						native = animation
					}
					return driver
				}
				let timeout = Task
				{
					do
					{
						try await Task.sleep(for: .seconds(3))
					}
					catch
					{
						return
					}
					continuation.finish()
				}
				defer
				{
					timeout.cancel()
					native?.delegate = nil
					continuation.finish()
				}
				let type: NSEvent.EventType = expanding ? .mouseEntered : .mouseExited
				let pointer = try event(
					type,
					slider: slider
				)
				if expanding
				{
					slider.mouseEntered(with: pointer)
				}
				else
				{
					slider.mouseExited(with: pointer)
				}
				let animation = try #require(native)
				#expect(animation.duration == (expanding ? 0.35 : 0.45))
				#expect(animation.animationBlockingMode == .nonblocking)
				var observed: [NativeHoverAnimationEvent] = []
				for await event in events
				{
					observed.append(event)
				}
				#expect(observed == [.progress(0.5), .completed])
				#expect(!animation.isAnimating)
				#expect(!slider.isAnimatingThumbHover)
				#expect(abs(slider.visualKnobDiameter - (expanding ? 32 : 28)) < 0.01)
				#expect(slider.doubleValue == 2)
			}
		}
	}

	@Test func closingPresentationAndDetachingCancelHover() throws
	{
		let fixture = Fixture()
		defer
		{
			fixture.close()
		}
		let slider = fixture.slider
		slider.shouldReduceMotion =
		{
			false
		}
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		slider.isPresented = false
		#expect(!slider.isAnimatingThumbHover)
		#expect(slider.visualKnobDiameter == 28)
		slider.isPresented = true
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		slider.removeFromSuperview()
		#expect(!slider.isAnimatingThumbHover)
		#expect(slider.visualKnobDiameter == 28)
	}

	private func event(
		_ type: NSEvent.EventType,
		slider: EffortSlider,
		point: NSPoint? = nil
	) throws -> NSEvent
	{
		let window = try #require(slider.window)
		let cell = try #require(slider.cell as? EffortSliderCell)
		let knob = cell.knobRect(flipped: slider.isFlipped)
		let location = slider.convert(
			point ?? NSPoint(
				x: knob.midX,
				y: knob.midY
			),
			to: nil
		)
		if type == .mouseMoved
		{
			return try #require(NSEvent.mouseEvent(
				with: type,
				location: location,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 0,
				clickCount: 0,
				pressure: 0
			))
		}
		return try #require(NSEvent.enterExitEvent(
			with: type,
			location: location,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
	}

	@MainActor private final class Fixture
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 230,
				height: 100
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		let slider = EffortSlider(frame: NSRect(
			x: 0,
			y: 36,
			width: 230,
			height: 28
		))

		init()
		{
			_ = NSApplication.shared
			window.isReleasedWhenClosed = false
			window.contentView?.addSubview(slider)
			slider.cell = EffortSliderCell()
			slider.minValue = 0
			slider.maxValue = 3
			slider.numberOfTickMarks = 4
			slider.doubleValue = 2
			slider.needsLayout = true
			slider.layoutSubtreeIfNeeded()
			window.orderFront(nil)
			slider.isPresented = true
		}

		func close()
		{
			slider.isPresented = false
			window.orderOut(nil)
			window.close()
		}
	}
}

private enum NativeHoverAnimationEvent: Equatable, Sendable
{
	case progress(NSAnimation.Progress)
	case completed
	case stopped
}

private final class NativeHoverAnimationObserver: NSObject, NSAnimationDelegate
{
	private let continuation: AsyncStream<NativeHoverAnimationEvent>.Continuation

	init(continuation: AsyncStream<NativeHoverAnimationEvent>.Continuation)
	{
		self.continuation = continuation
	}

	func animation(
		_ animation: NSAnimation,
		didReachProgressMark progress: NSAnimation.Progress
	)
	{
		continuation.yield(.progress(progress))
	}

	func animationDidEnd(_ animation: NSAnimation)
	{
		continuation.yield(.completed)
		continuation.finish()
	}

	func animationDidStop(_ animation: NSAnimation)
	{
		continuation.yield(.stopped)
		continuation.finish()
	}
}

/// Delivers controlled frames through the actual native spring interpolator.
@MainActor
private final class ControlledHoverAnimation: EffortThumbHoverAnimating
{
	private let native: EffortThumbHoverAnimation
	private(set) var isAnimating = false
	var onProgress: (@MainActor @Sendable (CGFloat) -> Void)?
	{
		get
		{
			native.onProgress
		}
		set
		{
			native.onProgress = newValue
		}
	}

	init(expanding: Bool)
	{
		native = EffortThumbHoverAnimation(expanding: expanding)
	}

	func start()
	{
		isAnimating = true
	}

	func stop()
	{
		isAnimating = false
	}

	func advance(to progress: NSAnimation.Progress)
	{
		guard isAnimating
		else
		{
			return
		}
		native.currentProgress = progress
		if progress >= 1
		{
			isAnimating = false
		}
	}
}
