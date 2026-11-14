import AppKit

/// A selector with a clear action that replaces its leading image on hover.
@MainActor
final class DesktopClearableSelector: NSView
{
	let button: DesktopStyledButton = DesktopClearableSelectorButton(
		title: "Choose project",
		presentation: .contextSelection,
		size: .regular
	)
	let clearButton: DesktopStyledButton = DesktopClearableSelectorButton(
		title: "Don't work in a project",
		presentation: .glyphOnlyIcon,
		size: .compact
	)
	var onClear: (() -> Void)?
	var isClearable = false
	{
		didSet
		{
			updateReveal()
		}
	}
	private var tracking: NSTrackingArea?
	private var hovered = false

	init()
	{
		super.init(frame: .zero)
		(button as? DesktopClearableSelectorButton)?
			.onFocusChanged =
			{
				[weak self] in self?.updateReveal()
			}
		(clearButton as? DesktopClearableSelectorButton)?
			.onFocusChanged =
			{
				[weak self] in self?.updateReveal()
			}
		button.controlTooltip.shouldPresent =
		{
			[weak self] in
			guard let self, !clearButton.isHidden, let window
			else
			{
				return true
			}
			let point = convert(
				window.mouseLocationOutsideOfEventStream,
				from: nil
			)
			return !clearButton.frame.contains(point)
		}
		(clearButton as? DesktopClearableSelectorButton)?
			.onPointerChanged =
			{
				[weak self] entered in
				guard let self
				else
				{
					return
				}
				if entered
				{
					button.controlTooltip.dismiss()
				}
				else if hovered
				{
					button.controlTooltip.show()
				}
			}
		button.keyboardFocusPolicy = .dialog
		clearButton.keyboardFocusPolicy = .dialog
		button.symbol = .folder
		AppKitLayout.pin(
			button,
			to: self,
			inset: 0
		)
		clearButton.symbol = .xCircleFilledCrossedClose
		clearButton.toolTip = "Don't work in a project"
		clearButton.setAccessibilityLabel("Don't work in a project")
		clearButton.target = self
		clearButton.action = #selector(clear)
		addSubview(clearButton)
		clearButton.isHidden = true
	}
	required init?(coder: NSCoder)
	{
		nil
	}
	override var intrinsicContentSize: NSSize
	{
		button.intrinsicContentSize
	}
	func updateContent()
	{
		invalidateIntrinsicContentSize(); needsLayout = true; updateReveal()
	}
	override func layout()
	{
		super.layout()
		let rect = button.contentLayout(in: button.bounds).image ?? .zero
		let side = clearButton.intrinsicContentSize.width
		clearButton.frame = NSRect(
			x: rect.midX - side / 2,
			y: bounds.midY - side / 2,
			width: side,
			height: side
		)
	}
	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		tracking = DesktopHoverTracking.replace(
			in: self,
			previous: tracking
		)
	}
	override func mouseEntered(with event: NSEvent)
	{
		hovered = true; updateReveal()
	}
	override func mouseExited(with event: NSEvent)
	{
		hovered = false; updateReveal()
	}
	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow == nil
		{
			hovered = false; updateReveal()
		}
		super.viewWillMove(toWindow: newWindow)
	}
	override func viewDidHide()
	{
		super.viewDidHide(); hovered = false; updateReveal()
	}
	private func updateReveal()
	{
		let focused = window?.firstResponder === button || window?.firstResponder === clearButton
		let visible = isClearable && (hovered || focused) && button.isEnabled
		clearButton.isHidden = !visible
		button.hidesLeadingImage = visible
	}
	@objc private func clear()
	{
		onClear?()
	}
}

/// Rechecks focus after AppKit finishes transferring it between selector actions.
@MainActor
private final class DesktopClearableSelectorButton: DesktopStyledButton
{
	var onFocusChanged: (() -> Void)?
	var onPointerChanged: ((Bool) -> Void)?
	override func mouseEntered(with event: NSEvent)
	{
		super.mouseEntered(with: event)
		onPointerChanged?(true)
	}
	override func mouseExited(with event: NSEvent)
	{
		super.mouseExited(with: event)
		onPointerChanged?(false)
	}
	override func becomeFirstResponder() -> Bool
	{
		let result = super.becomeFirstResponder()
		DispatchQueue.main.async
		{
			[weak self] in self?.onFocusChanged?()
		}
		return result
	}
	override func resignFirstResponder() -> Bool
	{
		let result = super.resignFirstResponder()
		DispatchQueue.main.async
		{
			[weak self] in self?.onFocusChanged?()
		}
		return result
	}
}
