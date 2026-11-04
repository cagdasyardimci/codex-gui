import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct PresetSyntaxRendererTests
{
	@Test func defaultSwiftThemePreservesLabelsStringsAndComments() throws
	{
		let source = "selection: .interface(weight: .medium), "
			+ "value: \"selection:\" // selection: 42\n"
		let rendered = try #require(CodeSyntaxHighlighter.highlightedCode(
			source,
			language: "swift",
			dark: true,
			configuration: ColorThemeConfiguration()
		))
		#expect(Data(rendered.string.utf8) == Data(source.utf8))
		for (fragment, hex): (String, UInt32) in [
			("selection:", 0xFA994C),
			("weight:", 0xFA994C),
			("\"selection:", 0x85DF7B),
			("// selection:", 0x999999)
		]
		{
			let range = (source as NSString).range(of: fragment)
			let color = try #require((rendered.attribute(
				.foregroundColor,
				at: range.location,
				effectiveRange: nil
			) as? NSColor)?.usingColorSpace(.sRGB))
			let expected = try #require(AppKitColorResolution
				.hexColor(String(
					format: "#%06X",
					hex
				))?.usingColorSpace(.sRGB))
			#expect(color == expected)
		}
	}

	@Test(arguments: [
		("Codex Dark", 0xF67576, 0x85DF7B),
		("Lobster Dark", 0xFF5C5C, 0x14B8A6),
	])
	func appliesMeasuredThemeRoles(
		_ id: String,
		keyword: UInt32,
		string: UInt32
	) throws
	{
		let source = "const name = \"x\"; // & < 😄\r\n"
		let rendered = try #require(PresetSyntaxRenderer.highlight(
			source,
			language: "javascript",
			themeID: id
		))
		#expect(Data(rendered.string.utf8) == Data(source.utf8))
		func expectColor(
			_ offset: Int,
			_ hex: UInt32
		) throws
		{
			let color = try #require((rendered.attribute(
				.foregroundColor,
				at: offset,
				effectiveRange: nil
			) as? NSColor)?.usingColorSpace(.sRGB))
			let channels = [color.redComponent, color.greenComponent, color.blueComponent]
			let expected = [
				CGFloat((hex >> 16) & 255),
				CGFloat((hex >> 8) & 255),
				CGFloat(hex & 255)
			]
			for (actual, value) in zip(
				channels,
				expected
			)
			{
				#expect(abs(actual * 255 - value) < 0.5)
			}
		}
		try expectColor(
			0,
			keyword
		)
		try expectColor(
			13,
			string
		)
	}

	@Test func rejectsUnknownThemeWithoutChangingSource()
	{
		#expect(PresetSyntaxRenderer
			.highlight(
				"x",
				language: "javascript",
				themeID: "unknown"
			) == nil)
	}

	@Test func markdownJavaScriptUsesMeasuredTokenColorsAndPreservesSource() throws
	{
		let source = "D = darkMode ? 60 : 45 // darkMode = 0\n"
		let result = try #require(PresetSyntaxRenderer.markdownDark(
			source,
			language: "javascript",
			foreground: 0xE4E4E7
		))
		#expect(Data(result.string.utf8) == Data(source.utf8))
		let expected: [(String, UInt32)] = [
			("D", 0xF1A275),
			("=", 0xF8A6C8),
			("darkMode", 0xB897F4),
			("60", 0xF1A275),
			("//", 0xB9B9B9)
		]
		for (fragment, hex) in expected
		{
			let range = (source as NSString).range(of: fragment)
			let value = try #require((result.attribute(
				.foregroundColor,
				at: range.location,
				effectiveRange: nil
			) as? NSColor)?.usingColorSpace(.sRGB))
			#expect(abs(value.redComponent * 255 - CGFloat((hex >> 16) & 255)) < 0.5)
			#expect(abs(value.greenComponent * 255 - CGFloat((hex >> 8) & 255)) < 0.5)
			#expect(abs(value.blueComponent * 255 - CGFloat(hex & 255)) < 0.5)
		}
	}

	@Test func markdownHighlightDoesNotPolluteSourceHighlightCache() throws
	{
		let source = "const cacheProbe = 60; // original"
		let baselineSource = "const cacheProbe = 60; // baseline"
		let baseline = try #require(CodeSyntaxHighlighter.highlightedCode(
			baselineSource,
			language: "javascript",
			dark: true
		))
		_ = try #require(CodeSyntaxHighlighter.highlightedCode(
			source,
			language: "javascript",
			dark: true,
			usePreset: false
		))
		let result = try #require(CodeSyntaxHighlighter.highlightedCode(
			source,
			language: "javascript",
			dark: true
		))
		let offset = (source as NSString).range(of: "60").location
		let actual = try #require((result.attribute(
			.foregroundColor,
			at: offset,
			effectiveRange: nil
		) as? NSColor)?.usingColorSpace(.sRGB))
		let expected = try #require((baseline.attribute(
			.foregroundColor,
			at: offset,
			effectiveRange: nil
		) as? NSColor)?.usingColorSpace(.sRGB))
		#expect(actual == expected)
	}

	@Test(arguments: [("Xcode Dark", CGFloat(1)), ("Xcode Light", CGFloat(0))])
	func eightDigitForegroundKeepsSourceAndOpacity(
		id: String,
		channel: CGFloat
	) throws
	{
		let source = "const value = 1;"
		let result = try #require(PresetSyntaxRenderer.highlight(
			source,
			language: "javascript",
			themeID: id
		))
		#expect(Data(result.string.utf8) == Data(source.utf8))
		let color = try #require((result.attribute(
			.foregroundColor,
			at: 5,
			effectiveRange: nil
		) as? NSColor)?.usingColorSpace(.sRGB))
		#expect(abs(color.redComponent - channel) < 0.001)
		#expect(abs(color.greenComponent - channel) < 0.001)
		#expect(abs(color.blueComponent - channel) < 0.001)
		#expect(abs(color.alphaComponent - 217.0 / 255) < 0.001)
	}
}
