import AppKit

/// A settings range input owns its slider, trailing value and accessory geometry.
@MainActor
final class SettingsSliderInput: NSView
{
	let slider = DesktopSlider(
		value: 60,
		minValue: 0,
		maxValue: 100,
		target: nil,
		action: nil
	)
	private let valueLabel = DesktopLineBoxLabel(
		"",
		role: TypographyTokens.Connections.body
	)

	var value: Int
	{
		get
		{
			slider.integerValue
		}
		set
		{
			slider.integerValue = newValue; valueLabel.stringValue = String(newValue)
		}
	}

	override init(frame frameRect: NSRect)
	{
		super.init(frame: frameRect)
		slider.widthAnchor.constraint(equalToConstant: 146).isActive = true
		valueLabel.alignment = .right
		valueLabel.widthAnchor.constraint(equalToConstant: 30).isActive = true
		AppKitLayout.pin(
			AppKitLayout.horizontalStack(
				[slider, valueLabel],
				spacing: 16
			),
			to: self,
			inset: 0
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
