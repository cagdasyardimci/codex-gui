import AppKit

/// A partial ring whose rotation is confined to the lifetime of a visible running task.
final class TaskProgressRingView: NSView
{
	private let ring = CAShapeLayer()
	private(set) var isRunning = false

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		wantsLayer = true
		ring.fillColor = nil
		ring.lineWidth = 1.5
		ring.lineCap = .round
		layer?.addSublayer(ring)
		isHidden = true
		setAccessibilityElement(false)
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	func setRunning(_ running: Bool)
	{
		isRunning = running
		isHidden = !running
		updateRotation()
	}

	override func layout()
	{
		super.layout()
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		ring.frame = bounds
		ring.path = CGPath(
			ellipseIn: bounds.insetBy(
				dx: 1.5,
				dy: 1.5
			),
			transform: nil
		)
		ring.strokeStart = 0.08
		ring.strokeEnd = 0.88
		ring.strokeColor = NSColor.secondaryLabelColor.cgColor
		CATransaction.commit()
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		needsLayout = true
	}

	override func viewDidMoveToWindow()
	{
		super.viewDidMoveToWindow()
		updateRotation()
	}

	private func updateRotation()
	{
		guard isRunning, window != nil
		else
		{
			ring.removeAnimation(forKey: "taskRotation")
			return
		}
		guard ring.animation(forKey: "taskRotation") == nil
		else
		{
			return
		}
		let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
		rotation.fromValue = 0
		rotation.toValue = Double.pi * 2
		rotation.duration = 1
		rotation.repeatCount = .infinity
		ring.add(
			rotation,
			forKey: "taskRotation"
		)
	}
}
