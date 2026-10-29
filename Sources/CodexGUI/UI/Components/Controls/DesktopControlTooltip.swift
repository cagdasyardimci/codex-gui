import AppKit

/// Adapts hover and native focus to one passive tooltip without registering an AppKit tooltip.
@MainActor
final class DesktopControlTooltip: NSObject
{
	let presentation = DesktopTooltip(style: .control)
	var text: String?
	{
		didSet
		{
			if oldValue != text
			{
				presentation.dismiss()
			}
		}
	}
	private weak var control: NSControl?
	private var tracking: NSTrackingArea?
	private var hovered = false
	private var focused = false

	func bind(to control: NSControl)
	{
		self.control = control
	}

	func updateTracking(in control: NSControl)
	{
		if let tracking
		{
			self.control?.removeTrackingArea(tracking)
		}
		self.control = control
		let area = NSTrackingArea(
			rect: .zero,
			options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
			owner: self,
			userInfo: nil
		)
		control.addTrackingArea(area)
		tracking = area
	}

	@objc(mouseEntered:) func mouseEntered(with event: NSEvent)
	{
		hovered = true
		show()
	}

	@objc(mouseExited:) func mouseExited(with event: NSEvent)
	{
		hovered = false
		presentation.dismiss()
	}

	func focusChanged(
		_ focused: Bool,
		in control: NSControl
	)
	{
		self.control = control
		self.focused = focused
		if focused
		{
			show(immediately: true)
		}
		else
		{
			presentation.dismiss()
		}
	}

	func dismiss()
	{
		presentation.dismiss()
	}

	func detach()
	{
		presentation.dismiss()
		hovered = false
		focused = false
		if let tracking
		{
			control?.removeTrackingArea(tracking)
		}
		tracking = nil
		control = nil
	}

	func show(immediately: Bool = false)
	{
		guard let control, control.isEnabled, let text, !text.isEmpty
		else
		{
			return
		}
		presentation.show(
			text,
			relativeTo: control,
			immediately: immediately
		)
		{
			[weak self, weak control] in
			guard let self, let control, control.isEnabled
			else
			{
				return false
			}
			return self.hovered || (self.focused && control.window?.firstResponder === control)
		}
	}
}
