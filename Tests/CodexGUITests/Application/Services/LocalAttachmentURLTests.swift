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
}
