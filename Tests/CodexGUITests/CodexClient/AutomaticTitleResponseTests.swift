import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AutomaticTitleResponseTests
{
	@Test func protocolTitleParsingRejectsMalformedOrEmptyOutput()
	{
		#expect(AutomaticTitleResponse.title("{\"title\":\" Create   placeholder \"}")
			== "Create placeholder")
		#expect(AutomaticTitleResponse.title("{\"title\":\"  \"}") == nil)
		#expect(AutomaticTitleResponse.title("Do something else") == nil)
		#expect(AutomaticTitleResponse.title("{\"title\":12}") == nil)
	}
}
