import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationAdaptiveTokenColorTests
{
	@Test func mergedRangesPreserveBothVariantsAndUTF16Offsets() throws
	{
		_ = NSApplication.shared
		let source = "a😀b café\n"
		let light = NSMutableAttributedString(string: source)
		let dark = NSMutableAttributedString(string: source)
		light.addAttribute(
			.foregroundColor,
			value: NSColor.red,
			range: NSRange(
				location: 0,
				length: 4
			)
		)
		light.addAttribute(
			.foregroundColor,
			value: NSColor.blue,
			range: NSRange(
				location: 4,
				length: 3
			)
		)
		dark.addAttribute(
			.foregroundColor,
			value: NSColor.green,
			range: NSRange(
				location: 1,
				length: 5
			)
		)
		// Other attributes must not introduce foreground-color interval boundaries.
		light.addAttribute(
			.underlineStyle,
			value: 1,
			range: NSRange(
				location: 1,
				length: 2
			)
		)
		dark.addAttribute(
			.foregroundColor,
			value: "not a color",
			range: NSRange(
				location: 7,
				length: 1
			)
		)
		let prefix = "😀:"
		let offset = (prefix as NSString).length
		let output = NSMutableAttributedString(string: prefix + source + "suffix")
		MarkdownAttributedStringRenderer.applyAdaptiveTokenColors(
			light: light,
			dark: dark,
			to: output,
			at: offset
		)
		#expect(output.string == prefix + source + "suffix")
		#expect(output.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) == nil)
		#expect(output.attribute(
			.foregroundColor,
			at: offset + light.length,
			effectiveRange: nil
		) == nil)
		var boundaries: Set<Int> = [0, light.length]
		for variant in [light, dark]
		{
			variant.enumerateAttribute(
				.foregroundColor,
				in: NSRange(
					location: 0,
					length: light.length
				),
				options: []
			)
			{
				_, range, _ in
				boundaries.insert(range.location)
				boundaries.insert(NSMaxRange(range))
			}
		}
		var actualBoundaries: Set<Int> = [0, light.length]
		output.enumerateAttribute(
			.foregroundColor,
			in: NSRange(
				location: offset,
				length: light.length
			),
			options: []
		)
		{
			_, range, _ in
			actualBoundaries.insert(range.location - offset)
			actualBoundaries.insert(NSMaxRange(range) - offset)
		}
		#expect(actualBoundaries == boundaries)
		for (name, variant) in [(NSAppearance.Name.aqua, light), (.darkAqua, dark)]
		{
			let appearance = try #require(NSAppearance(named: name))
			appearance.performAsCurrentDrawingAppearance
			{
				for index in 0 ..< light.length
				{
					let expected = variant.attribute(
						.foregroundColor,
						at: index,
						effectiveRange: nil
					) as? NSColor ?? .labelColor
					let actual = output.attribute(
						.foregroundColor,
						at: offset + index,
						effectiveRange: nil
					) as? NSColor
					#expect(actual?.usingColorSpace(.deviceRGB)
						== expected.usingColorSpace(.deviceRGB))
				}
			}
		}
	}

	@Test func emptyVariantsLeaveDestinationUntouched()
	{
		let output = NSMutableAttributedString(string: "untouched")
		let empty = NSAttributedString(string: "")
		MarkdownAttributedStringRenderer.applyAdaptiveTokenColors(
			light: empty,
			dark: empty,
			to: output,
			at: 0
		)
		#expect(output.string == "untouched")
		#expect(output.attribute(
			.foregroundColor,
			at: 0,
			effectiveRange: nil
		) == nil)
	}
}
