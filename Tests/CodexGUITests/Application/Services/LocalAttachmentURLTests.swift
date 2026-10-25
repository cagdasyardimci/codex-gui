import Foundation
import Testing

@testable import CodexGUI

@Suite
struct LocalAttachmentURLTests
{

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
