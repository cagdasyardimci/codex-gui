import AppKit
import QuartzCore
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
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
		slider.shouldReduceMotion =
		{
			false
		}
		slider.mouseEntered(with: try event(
			.mouseEntered,
			slider: slider
		))
		#expect(slider.isAnimatingThumbHover)
		pump(for: 0.1)
		#expect(slider.visualKnobDiameter > 28)
		#expect(slider.visualKnobDiameter < 32)
		pump(for: 0.35)
		#expect(abs(slider.visualKnobDiameter - 32) < 0.01)
		#expect(!slider.isAnimatingThumbHover)
		slider.mouseExited(with: try event(
			.mouseExited,
			slider: slider
		))
		pump(for: 0.1)
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
		pump(for: 0.5)
		#expect(slider.visualKnobDiameter == 28)
		#expect(slider.doubleValue == 2)
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

	private func pump(for duration: TimeInterval)
	{
		RunLoop.current.run(until: Date().addingTimeInterval(duration))
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
