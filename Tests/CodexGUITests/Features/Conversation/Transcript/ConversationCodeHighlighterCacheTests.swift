import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationCodeHighlighterCacheTests
{
	@Test func unchangedCodeReusesColorsAcrossLanguageAliasesAndSeparatesAppearances() throws
	{
		_ = NSApplication.shared
		let source = "const message = \"café 😀\";\nconsole.log(message);\n"
		let light = try highlight(
			source,
			language: "js",
			dark: false
		)
		let repeated = try highlight(
			source,
			language: "JavaScript extra-info",
			dark: false
		)
		let dark = try highlight(
			source,
			language: "javascript",
			dark: true
		)
		#expect(light === repeated)
		#expect(light !== dark)
		#expect(light.string.utf8.elementsEqual(source.utf8))
		#expect(dark.string.utf8.elementsEqual(source.utf8))
		#expect(light.attributes(
			at: 0,
			effectiveRange: nil
		).keys.allSatisfy
		{
			$0 == .foregroundColor
		})
		let range = (source as NSString).range(of: "const")
		let lightColor = try #require(light.attribute(
			.foregroundColor,
			at: range.location,
			effectiveRange: nil
		) as? NSColor)
		let darkColor = try #require(dark.attribute(
			.foregroundColor,
			at: range.location,
			effectiveRange: nil
		) as? NSColor)
		#expect(lightColor != darkColor)
	}

	@Test func canonicallyEquivalentUnicodeCodeRetainsItsExactOriginalBytes() throws
	{
		_ = NSApplication.shared
		let composed = "let message = \"caf\u{E9}\"\n"
		let decomposed = "let message = \"cafe\u{301}\"\n"
		#expect(composed == decomposed)
		#expect(!composed.utf8.elementsEqual(decomposed.utf8))
		let first = try highlight(composed)
		let second = try highlight(decomposed)
		#expect(first !== second)
		#expect(first.string.utf8.elementsEqual(composed.utf8))
		#expect(second.string.utf8.elementsEqual(decomposed.utf8))
		#expect(try highlight(composed) === first)
	}

	@Test func activeCodeSurvivesStreamChurnWhileUnusedColorsAreReleased() throws
	{
		_ = NSApplication.shared
		let identity = UUID().uuidString
		let activeSource = "// active \(identity)\nlet active = 42\n"
		let unusedSource = "// unused \(identity)\nlet unused = 41\n"
		let unused = try highlight(unusedSource)
		let active = try highlight(activeSource)
		for version in 0 ..< 80
		{
			#expect(try highlight(activeSource) === active)
			_ = try highlight("// streamed \(identity)\nlet version = \(version)\n")
		}
		#expect(try highlight(activeSource) === active)
		let reloaded = try highlight(unusedSource)
		#expect(reloaded !== unused)
		#expect(reloaded.isEqual(to: unused))
	}

	@Test func largeTokenRunsEvictUnusedColorsBeforeTheEntryLimit() throws
	{
		_ = NSApplication.shared
		let identity = UUID().uuidString
		let source = "// original \(identity)\nlet original = 1\n"
		let original = try highlight(source)
		let code = String(
			repeating: "let value = 42\n",
			count: 800
		)
		for version in 0 ..< 10
		{
			_ = try highlight("// large \(identity) version \(version)\n" + code)
		}
		let reloaded = try highlight(source)
		#expect(reloaded !== original)
		#expect(reloaded.isEqual(to: original))
	}

	private func highlight(
		_ source: String,
		language: String = "swift",
		dark: Bool = false
	) throws -> NSAttributedString
	{
		try #require(ConversationCodeHighlighter.highlightedCode(
			source,
			language: language,
			dark: dark
		))
	}
}
