import AppKit
import CoreText
import Testing

@testable import CodexGUI

struct FontWeightMatchingTests
{
	@Test func mediumRequestsPreferRegularBeforeBold()
	{
		#expect(FontWeightMatching.match(
			430,
			available: [400, 700]
		) == 400)
		#expect(FontWeightMatching.match(
			500,
			available: [400, 700]
		) == 400)
		#expect(FontWeightMatching.match(
			600,
			available: [400, 700]
		) == 700)
		#expect(FontWeightMatching.match(
			430,
			available: [400, 500, 700]
		) == 500)
		#expect(FontWeightMatching.match(
			400,
			available: [300, 500, 600]
		) == 500)
		#expect(FontWeightMatching.match(
			600,
			available: [400, 500]
		) == 500)
		#expect(FontWeightMatching.match(
			300,
			available: [200, 400]
		) == 200)
		#expect(FontWeightMatching.match(
			430,
			available: []
		) == nil)
	}
}

@MainActor
struct TypographyWeightTests
{
	@Test(arguments: ["Arial", "Helvetica", "Chalkboard", "Menlo"])
	func staticFamiliesCollapseTextAndMediumButRetainStrong(_ family: String) throws
	{
		let expected: [String: [String]] = [
			"Arial": ["ArialMT", "Arial-BoldMT"],
			"Helvetica": ["Helvetica", "Helvetica-Bold"],
			"Chalkboard": ["Chalkboard", "Chalkboard-Bold"],
			"Menlo": ["Menlo-Regular", "Menlo-Bold"],
		]
		let names = try #require(expected[family])
		for weight in [TypographyTokens.Weight.regular, .text, .medium, .strong]
		{
			let role = TypographyTokens.Role(
				size: 14,
				selection: .family(
					family,
					weight: weight
				)
			)
			for size: CGFloat in [11, 16]
			{
				let font = AppKitFontResolver.font(
					role,
					configuration: .init(uiSize: size)
				)
				#expect(font.fontName == names[weight == .strong ? 1 : 0])
				#expect(font.pointSize == size)
			}
		}
	}

	@Test(arguments: ["Arial", "Helvetica", "Menlo"])
	func italicUsesRealCompanionFaces(_ family: String)
	{
		let expected = [
			"Arial": ["Arial-ItalicMT", "Arial-BoldItalicMT"],
			"Helvetica": ["Helvetica-Oblique", "Helvetica-BoldOblique"],
			"Menlo": ["Menlo-Italic", "Menlo-BoldItalic"],
		]
		for (index, weight) in [TypographyTokens.Weight.text, .strong].enumerated()
		{
			let font = AppKitFontResolver.familyFont(
				family,
				size: 14,
				weight: weight,
				italic: true
			)
			#expect(font.fontName == expected[family]?[index])
		}
	}

	@Test func systemRetainsExactWeightAxesAndBoldItalicCompanion() throws
	{
		for weight in [TypographyTokens.Weight.regular, .text, .medium, .strong]
		{
			let font = AppKitFontResolver.interfaceFont(
				ofSize: 14,
				weight: weight
			)
			#expect(try axisValue(
				font,
				identifier: 0x77676874
			) == weight.rawValue)
			#expect(try axisValue(
				font,
				identifier: 0x6F70737A
			) == 17)
		}
		let italic = AppKitFontResolver.interfaceFont(
			ofSize: 14,
			weight: .strong,
			italic: true
		)
		let axes = try #require(CTFontCopyVariation(italic as CTFont) as? [NSNumber: NSNumber])
		#expect(axes[NSNumber(value: 0x77676874)]?.intValue == 600)
		#expect(axes[NSNumber(value: 0x59415853)]?.intValue == 430)
	}

	private func axisValue(
		_ font: NSFont,
		identifier: Int
	) throws -> Int
	{
		// CoreText omits axes at their default value from the current variation dictionary.
		let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
		if let value = variations?[NSNumber(value: identifier)]
		{
			return value.intValue
		}
		let axes = try #require(CTFontCopyVariationAxes(font as CTFont) as? [[String: Any]])
		let definition = try #require(axes.first
		{
			($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == identifier
		})
		return try #require(definition[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber)
			.intValue
	}

	private func font(
		in text: NSAttributedString,
		sample: String
	) throws -> NSFont
	{
		let range = (text.string as NSString).range(of: sample)
		try #require(range.location != NSNotFound)
		return try #require(text.attribute(
			.font,
			at: range.location,
			effectiveRange: nil
		) as? NSFont)
	}
}
