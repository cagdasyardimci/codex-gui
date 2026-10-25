import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@Suite(
	.serialized
) @MainActor
struct EffortSliderHoverTests
{

	@Test(.timeLimit(.minutes(1)))
	func defaultHoverDriverDeliversScheduledFramesAndCompletesBothTransitions() async throws
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
				let (events, continuation) = AsyncStream<CGFloat>.makeStream()
				var native: EffortThumbHoverAnimation?
				// Retain the production factory's actual scheduled driver.
				slider.makeHoverAnimation =
				{
					expanding in
					let driver = defaultFactory(expanding)
					if let animation = driver as? EffortThumbHoverAnimation
					{
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
				let originalProgress = animation.onProgress
				animation.onProgress =
				{
					[weak animation] progress in
					originalProgress?(progress)
					continuation.yield(progress)
					if animation?.isAnimating == false
					{
						continuation.finish()
					}
				}
				defer
				{
					animation.onProgress = originalProgress
				}
				var observed: [CGFloat] = []
				for await event in events
				{
					observed.append(event)
				}
				#expect(observed.contains
				{
					$0 > 0 && $0 < 1
				})
				#expect(observed.last == 1)
				#expect(!animation.isAnimating)
				#expect(!slider.isAnimatingThumbHover)
				#expect(abs(slider.visualKnobDiameter - (expanding ? 32 : 28)) < 0.01)
				#expect(slider.doubleValue == 2)
			}
		}
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
			window.prepareForTesting()
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

/// Delivers controlled frames through the production spring interpolator.
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

	func advance(to progress: Float)
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
