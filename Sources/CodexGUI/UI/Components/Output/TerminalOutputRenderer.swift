import AppKit

/// Interprets streamed terminal control sequences without turning them into visible text or links.
@MainActor
struct TerminalOutputRenderer
{
	private enum State
	{
		case text, escape, csi, osc, oscEscape
	}

	private var state = State.text
	private var parameters = ""
	private var emphasized = false

	mutating func append(
		_ source: String,
		configuration: TypographyConfiguration = .current,
		appearance: NSAppearance? = nil
	) -> NSAttributedString
	{
		let result = NSMutableAttributedString(string: "")
		var text = ""
		func flush()
		{
			guard !text.isEmpty
			else
			{
				return
			}
			let role = TypographyTokens.Terminal.output(emphasized: emphasized)
			let font = AppKitFontResolver.font(
				role,
				configuration: configuration,
				appearance: appearance
			)
			var attributes = AppKitFontResolver.textAttributes(
				role,
				font: font,
				configuration: configuration
			)
			attributes[.foregroundColor] = AppKitColorTokens.terminalOutputText
			result.append(NSAttributedString(
				string: text,
				attributes: attributes
			))
			text = ""
		}
		for scalar in source.unicodeScalars
		{
			switch state
			{
			case .text:
				if scalar.value == 0x1b
				{
					state = .escape
				}
				else if scalar.value == 0x9b
				{
					parameters = ""
					state = .csi
				}
				else
				{
					text.unicodeScalars.append(scalar)
				}
			case .escape:
				if scalar == "["
				{
					parameters = ""
					state = .csi
				}
				else
				{
					state = scalar == "]" ? .osc : .text
				}
			case .csi:
				if (0x40 ... 0x7e).contains(scalar.value)
				{
					if scalar == "m"
					{
						flush()
						let values = parameters.split(
							separator: ";",
							omittingEmptySubsequences: false
						)
						var index = 0
						while index < values.count
						{
							let value = values[index]
							switch value.isEmpty ? 0 : Int(value)
							{
							case 0, 22: emphasized = false
							case 1: emphasized = true
							case 38, 48, 58:
								// Skip color operands; ink stays theme-owned.
								if index + 1 < values.count
								{
									switch values[index + 1]
									{
									case "2": index += 4
									case "5": index += 2
									default: break
									}
								}
							default: break
							}
							index += 1
						}
					}
					state = .text
				}
				else if parameters.utf8.count < 128
				{
					parameters.unicodeScalars.append(scalar)
				}
			case .osc:
				if scalar.value == 7
				{
					state = .text
				}
				else if scalar.value == 0x1b
				{
					state = .oscEscape
				}
			case .oscEscape:
				state = scalar == "\\" ? .text : .osc
			}
		}
		flush()
		return result
	}
}
