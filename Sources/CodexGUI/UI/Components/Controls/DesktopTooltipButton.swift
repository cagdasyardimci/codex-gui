import AppKit

/// Shared tooltip lifecycle for buttons, preserving native actions and focus traversal.
@MainActor
class DesktopTooltipButton: NSButton
{
	let controlTooltip = DesktopControlTooltip()
	var tooltipShortcut: String?
	{
		get
		{
			controlTooltip.presentation.shortcut
		}
		set
		{
			controlTooltip.dismiss()
			controlTooltip.presentation.shortcut = newValue
		}
	}
	var tooltipPlacement: DesktopTooltip.Placement
	{
		get
		{
			controlTooltip.presentation.placement
		}
		set
		{
			controlTooltip.presentation.placement = newValue
		}
	}
	var tooltipTask: Task<Void, Never>?
	{
		controlTooltip.presentation.task
	}
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
	override func mouseEntered(with event: NSEvent)
	{
		controlTooltip.bind(to: self)
		controlTooltip.mouseEntered(with: event)
	}
	override func mouseExited(with event: NSEvent)
	{
		controlTooltip.mouseExited(with: event)
	}
	override func mouseDown(with event: NSEvent)
	{
		controlTooltip.dismiss()
		super.mouseDown(with: event)
		controlTooltip.dismiss()
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
}
