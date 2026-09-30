import Testing

@testable import CodexGUI

struct UserMessagePresenterTests
{
	@Test func presenterRetainsReferencesWithoutMatchingDescriptions()
	{
		let inputs: [TurnInput] = [
			.text("File reference: Other.swift\nAttached image: First screenshot"),
			.mention(
				name: "Example.swift",
				path: "/tmp/Example.swift"
			),
			.localImage(path: "/tmp/first.png"),
			.localImage(path: "/tmp/second.png"),
		]
		let body = UserMessagePresenter.body(for: inputs)
		#expect(body.contains("[File reference: Example.swift]"))
		#expect(!body.contains("[Image: first.png]"))
		#expect(body.contains("[Image: second.png]"))
	}

	@Test func presenterRecognizesTheDisplayNameOfAResolvedFileAlias()
	{
		let inputs: [TurnInput] = [
			.text("File reference: Sources/Alias.swift"),
			.mention(
				name: "Alias.swift",
				path: "/tmp/project/Sources/Original.swift"
			),
		]
		#expect(UserMessagePresenter.body(for: inputs) == "File reference: Sources/Alias.swift")
	}
}
