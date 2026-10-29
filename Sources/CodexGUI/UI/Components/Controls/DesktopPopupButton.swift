import AppKit

/// Complete native inline popup presentation; callers own menu data and selection routing.
@MainActor
class DesktopPopupButton: NSPopUpButton
{
	let controlTooltip = DesktopControlTooltip()
	override var toolTip: String?
	{
		get
		{
			controlTooltip.text
		}
		set
		{
			controlTooltip.text = newValue
		}
	}
	override var isEnabled: Bool
	{
		didSet
		{
			if !isEnabled
			{
				controlTooltip.dismiss()
			}
		}
	}
	override func updateTrackingAreas()
	{
		super.updateTrackingAreas()
		controlTooltip.updateTracking(in: self)
	}
	override func becomeFirstResponder() -> Bool
	{
		let accepted = super.becomeFirstResponder()
		if accepted
		{
			controlTooltip.focusChanged(
				true,
				in: self
			)
		}
		return accepted
	}
	override func resignFirstResponder() -> Bool
	{
		let accepted = super.resignFirstResponder()
		if accepted
		{
			controlTooltip.focusChanged(
				false,
				in: self
			)
		}
		return accepted
	}
	override func mouseDown(with event: NSEvent)
	{
		controlTooltip.dismiss()
		super.mouseDown(with: event)
		controlTooltip.dismiss()
	}
	override func viewWillMove(toWindow newWindow: NSWindow?)
	{
		if newWindow !== window
		{
			controlTooltip.detach()
		}
		super.viewWillMove(toWindow: newWindow)
	}
	override func viewDidHide()
	{
		controlTooltip.dismiss()
		super.viewDidHide()
	}

	enum Size
	{
		case compact, small
	}

	var size: Size = .compact
	{
		didSet
		{
			font = size == .small ? .systemFont(ofSize: 11)
				: AppKitFontResolver.font(TypographyTokens.Controls.button)
		}
	}

	convenience init()
	{
		self.init(
			frame: .zero,
			pullsDown: false
		)
	}

	override init(
		frame buttonFrame: NSRect,
		pullsDown flag: Bool
	)
	{
		super.init(
			frame: buttonFrame,
			pullsDown: flag
		)
		bezelStyle = .inline
		isBordered = false
		controlSize = .small
		font = AppKitFontResolver.font(TypographyTokens.Controls.button)
		contentTintColor = .secondaryLabelColor
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
