import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ThreadTitleTextTests
{
	@Test func provisionalTitleUsesNormalizedPromptAndPreservesUnicode()
	{
		#expect(ThreadTitleText
			.placeholder("  Fix\n\tbaşlık   updates  ") == "Fix başlık updates")
		#expect(ThreadTitleText.placeholder(" \n ") == "New chat")
		#expect(ThreadTitleText.placeholder(String(
			repeating: "👩🏽‍💻",
			count: 130
		)).count == 120)
	}
}
