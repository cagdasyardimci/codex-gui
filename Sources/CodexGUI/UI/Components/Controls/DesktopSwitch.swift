import AppKit

/// Retains NSButton's state, keyboard activation and target/action handling while
/// drawing the reference switch at its fixed visual size.
@MainActor
final class DesktopSwitch: NSButton
{
	private var thumbProgress: CGFloat = 0
	private var drawnState: NSControl.StateValue = .off
	private var animationTimer: Timer?
	private var colorObservation: ThemeColorObservation?
	private var focusIndicator: CAShapeLayer?
	private var keyboardFocused = false

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		colorObservation = ThemeColorObservation
		{
			[weak self] in
			self?.refreshFocusIndicator()
			self?.needsDisplay = true
		}
		setButtonType(.switch)
		title = ""
		isBordered = false
		focusRingType = .none
		setContentHuggingPriority(
			.required,
			for: .horizontal
		)
		setContentHuggingPriority(
			.required,
			for: .vertical
		)
		setContentCompressionResistancePriority(
			.required,
			for: .horizontal
		)
		setContentCompressionResistancePriority(
			.required,
			for: .vertical
		)
		setAccessibilityRole(NSAccessibility.Role(rawValue: "AXSwitch"))
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	isolated deinit
	{
		animationTimer?.invalidate()
	}

	override var alignmentRectInsets: NSEdgeInsets
	{
		NSEdgeInsets()
	}

	override var state: NSControl.StateValue
	{
		didSet
		{
			if oldValue != state
			{
				animateThumb()
			}
		}
	}

	override var isEnabled: Bool
	{
		didSet
		{
			if !isEnabled
			{
				finishAnimation()
			}
			refreshFocusIndicator()
			needsDisplay = true
		}
	}

	override var intrinsicContentSize: NSSize
	{
		NSSize(
			width: 32,
			height: 20
		)
	}

	private var trackBounds: NSRect
	{
		NSRect(
			x: bounds.midX - 16,
			y: bounds.midY - 10,
			width: 32,
			height: 20
		)
	}

	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			finishAnimation()
		}
		super.viewWillMove(toWindow: newWindow)
	}

	private func finishAnimation()
	{
		drawnState = state
		animationTimer?.invalidate()
		animationTimer = nil
		thumbProgress = state == .on ? 1 : 0
		needsDisplay = true
	}

	private func animateThumb()
	{
		drawnState = state
		animationTimer?.invalidate()
		animationTimer = nil
		guard window?.isVisible == true, isEnabled,
				!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		else
		{
			finishAnimation()
			return
		}
		let start = ProcessInfo.processInfo.systemUptime
		let initial = thumbProgress
		let target: CGFloat = state == .on ? 1 : 0
		let timer = Timer(
			timeInterval: 1 / 60.0,
			repeats: true
		)
		{
			[weak self] timer in
			let timerID = ObjectIdentifier(timer)
			MainActor.assumeIsolated
			{
				guard let self, let activeTimer = self.animationTimer,
						ObjectIdentifier(activeTimer) == timerID
				else
				{
					return
				}
				let elapsed = (ProcessInfo.processInfo.systemUptime - start) / 0.15
				guard elapsed < 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
				else
				{
					self.finishAnimation()
					return
				}
				self.thumbProgress = initial + (target - initial) * Self.easeOut(CGFloat(elapsed))
				self.needsDisplay = true
			}
		}
		animationTimer = timer
		RunLoop.main.add(
			timer,
			forMode: .common
		)
	}

	/// Inverts the x coordinate of the reference cubic-bezier(0, 0, 0.2, 1).
	private static func easeOut(_ progress: CGFloat) -> CGFloat
	{
		var lower: CGFloat = 0
		var upper: CGFloat = 1
		for _ in 0 ..< 20
		{
			let t = (lower + upper) / 2
			let x = 0.6 * t * t + 0.4 * t * t * t
			if x < progress
			{
				lower = t
			}
			else
			{
				upper = t
			}
		}
		let t = (lower + upper) / 2
		return 3 * t * t - 2 * t * t * t
	}

	override func viewDidChangeEffectiveAppearance()
	{
		super.viewDidChangeEffectiveAppearance()
		refreshFocusIndicator()
		needsDisplay = true
	}

	override func layout()
	{
		super.layout()
		refreshFocusIndicator()
	}

	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		keyboardFocused = accepted && NSApp.currentEvent?.type == .keyDown
		needsLayout = true
		refreshFocusIndicator()
		return accepted
	}

	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			keyboardFocused = false
		}
		needsLayout = true
		refreshFocusIndicator()
		return accepted
	}

	private func refreshFocusIndicator()
	{
		if focusIndicator == nil
		{
			wantsLayer = true
			let indicator = CAShapeLayer()
			indicator.fillColor = nil
			indicator.lineWidth = 2
			layer?.addSublayer(indicator)
			focusIndicator = indicator
		}
		guard let indicator = focusIndicator
		else
		{
			return
		}
		CATransaction.begin()
		CATransaction.setDisableActions(true)
		indicator.isHidden = !isEnabled || !keyboardFocused || window?.firstResponder !== self
		indicator.frame = bounds
		indicator.path = CGPath(
			roundedRect: trackBounds.insetBy(
				dx: -1,
				dy: -1
			),
			cornerWidth: 11,
			cornerHeight: 11,
			transform: nil
		)
		indicator.strokeColor = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.focus,
			for: self
		)
		CATransaction.commit()
	}

	override func draw(_ dirtyRect: NSRect)
	{
		if drawnState != state
		{
			animateThumb()
		}
		NSGraphicsContext.saveGraphicsState()
		defer
		{
			NSGraphicsContext.restoreGraphicsState()
		}
		bounds.clip()
		let track = trackBounds
		let on = state == .on
		let context = NSGraphicsContext.current?.cgContext
		context?.setAlpha(isEnabled ? 1 : 0.6)
		context?.beginTransparencyLayer(auxiliaryInfo: nil)
		defer
		{
			context?.endTransparencyLayer()
		}
		let trackColor = on
			? AppKitColorTokens.accent
			: AppKitColorTokens.switchOff
		trackColor.setFill()
		NSBezierPath(
			roundedRect: track,
			xRadius: 10,
			yRadius: 10
		).fill()
		let thumb = NSRect(
			x: track.minX + 2 + 12 * thumbProgress,
			y: track.minY + 2,
			width: 16,
			height: 16
		)
		AppKitColorTokens.switchThumb(on: on).setFill()
		// CSS shadow-sm: 0px 1px 2px -1px rgba(0, 0, 0, 0.08).
		let shadow = NSShadow()
		shadow.shadowColor = ShadowTokens.switchThumb.color
		shadow.shadowOffset = NSSize(
			width: 0,
			height: ShadowTokens.switchThumb.offsetY
		)
		shadow.shadowBlurRadius = ShadowTokens.switchThumb.blur
		shadow.set()
		NSBezierPath(ovalIn: thumb.insetBy(
			dx: 1,
			dy: 1
		)).fill()
		NSShadow().set()
		NSBezierPath(ovalIn: thumb).fill()
	}

	override var focusRingMaskBounds: NSRect
	{
		trackBounds
	}

	override func drawFocusRingMask()
	{
		NSBezierPath(
			roundedRect: trackBounds,
			xRadius: 10,
			yRadius: 10
		).fill()
	}
}
