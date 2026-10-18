import Foundation
import Testing

@testable import CodexGUI

@Suite
struct LocalAttachmentURLTests
{
	@Test func explicitLocalPathsAndFileURLsShareTheirCanonicalURL()
	{
		let expected = URL(fileURLWithPath: "/tmp/source image.png").standardizedFileURL
		for path in [
			"/tmp/other/../source image.png",
			"file:///tmp/source%20image.png",
			"file://localhost/tmp/source%20image.png",
		]
		{
			#expect(LocalAttachmentURL.resolve(path) == expected)
		}
		#expect(LocalAttachmentURL.resolve("~/source.png")?.path.hasPrefix(
			FileManager.default.homeDirectoryForCurrentUser.path
		) == true)
	}

	@Test func relativeRemoteAndInlineReferencesAreNeverLocalFiles()
	{
		for path in [
			"relative/source.png",
			"file:relative/source.png",
			"file://remote-host/tmp/source.png",
			"https://example.com/source.png",
			"data:image/png;base64,YQ==",
		]
		{
			#expect(LocalAttachmentURL.resolve(path) == nil)
		}
	}
	@Test func referenceIdentityMatchesLocalPathsAndDecodedFileURLs()
	{
		let expected = Data("/tmp/é #.png".utf8)
		for path in [
			"/tmp/é #.png",
			"file:///tmp/%C3%A9%20%23.png",
			"file://localhost/tmp/%C3%A9%20%23.png",
			"file:/tmp/%C3%A9%20%23.png",
		]
		{
			#expect(LocalAttachmentURL.referenceIdentity(path) == expected)
		}
	}

	@Test func referenceIdentityPreservesUnicodeSpellingBeforeAndAfterURLDecoding()
	{
		let composed = "/tmp/é.png"
		let decomposed = "/tmp/e\u{301}.png"
		let composedKey = LocalAttachmentURL.referenceIdentity(composed)
		let decomposedKey = LocalAttachmentURL.referenceIdentity(decomposed)
		#expect(composedKey == Data(composed.utf8))
		#expect(decomposedKey == Data(decomposed.utf8))
		#expect(composedKey != decomposedKey)
		#expect(LocalAttachmentURL.referenceIdentity("file:///tmp/%C3%A9.png") == composedKey)
		#expect(LocalAttachmentURL.referenceIdentity("file:///tmp/e%CC%81.png") == decomposedKey)
		#expect(LocalAttachmentURL.referenceIdentity("file:///tmp/é.png") == composedKey)
		#expect(LocalAttachmentURL.referenceIdentity("file:///tmp/e\u{301}.png") == decomposedKey)
	}

	@Test func referenceIdentityPreservesUnsupportedReferences()
	{
		for path in ["file://remote/tmp/image.png",
						"file:relative.png",
						"data:image/png;base64,AAAA"]
		{
			#expect(LocalAttachmentURL.referenceIdentity(path) == Data(path.utf8))
		}
	}

	@Test func referenceIdentityDeduplicatesLexicalLocalPathAliases()
	{
		let expected = Data("/tmp/source-types/folder".utf8)
		for path in [
			"/tmp/source-types/folder/",
			"file:///tmp/source-types/folder",
			"file:///tmp//source-types/./folder/",
			"/tmp/source-types/unused/../folder//",
			"/../tmp/source-types/folder",
		]
		{
			#expect(LocalAttachmentURL.referenceIdentity(path) == expected)
		}
		#expect(LocalAttachmentURL.referenceIdentity("/tmp/./é.png/") == Data("/tmp/é.png".utf8))
		#expect(LocalAttachmentURL.referenceIdentity("/tmp/unused/../e\u{301}.png")
			== Data("/tmp/e\u{301}.png".utf8))
	}

	@Test func referenceIdentityExpandsHomeWithoutRewritingUnicodeFilenameBytes()
	{
		let home = NSString(string: "~").expandingTildeInPath
		let composed = LocalAttachmentURL.referenceIdentity("~/é.png")
		let decomposed = LocalAttachmentURL.referenceIdentity("~/e\u{301}.png")
		#expect(composed == Data((home + "/é.png").utf8))
		#expect(decomposed == Data((home + "/e\u{301}.png").utf8))
		#expect(composed != decomposed)
	}

	@Test func referenceIdentityUsesByteSeparatorsBeforeCombiningMarkComponents()
	{
		let component = "\u{301}file.png"
		let expected = Data(("/tmp/" + component).utf8)
		for path in [
			"/tmp/" + component,
			"/tmp//" + component + "/",
			"/tmp/unused/../" + component,
			"file:///tmp/%CC%81file.png",
		]
		{
			#expect(LocalAttachmentURL.referenceIdentity(path) == expected)
		}
		#expect(LocalAttachmentURL.referenceIdentity("/" + component)
			== Data(("/" + component).utf8))
		#expect(LocalAttachmentURL.referenceIdentity("file:///%CC%81file.png")
			== Data(("/" + component).utf8))
		let home = NSString(string: "~").expandingTildeInPath
		#expect(LocalAttachmentURL.referenceIdentity("~/" + component)
			== Data((home + "/" + component).utf8))
	}

}
