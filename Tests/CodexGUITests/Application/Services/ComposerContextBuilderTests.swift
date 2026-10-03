import Foundation
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ComposerContextBuilderTests
{
	@Test func contextInputsKeepTypesAndLineNumbers() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let source = project.appendingPathComponent("Sources/Example.swift")
		try FileManager.default.createDirectory(
			at: source.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try "one\ntwo\nthree\n".write(
			to: source,
			atomically: true,
			encoding: .utf8
		)
		let image = project.appendingPathComponent("screenshot.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let items = [
			ComposerContextItem(
				kind: .fileReference,
				title: "Example.swift",
				path: "Sources/Example.swift"
			),
			ComposerContextItem(
				kind: .textExcerpt,
				title: "Example.swift",
				path: "Sources/Example.swift",
				firstLine: 2,
				lastLine: 3,
				excerpt: "two\nthree"
			),
			ComposerContextItem(
				kind: .image,
				title: "Screenshot",
				path: image.path
			),
		]

		let inputs = try ComposerContextBuilder.inputs(
			text: "Please inspect",
			items: items,
			project: project
		)
		#expect(inputs.count == 3)
		guard case .text(let text) = inputs[0]
		else
		{
			Issue.record("Expected text input")
			return
		}
		#expect(text.contains("Selected code from Sources/Example.swift, lines 2–3"))
		#expect(text.contains("2: two\n3: three"))
		#expect(inputs[1] == .mention(
			name: "Example.swift",
			path: source.path
		))
		#expect(inputs[2] == .localImage(path: image.path))
		#expect(inputs[2].protocolValue["type"] as? String == "localImage")

		let history = try #require(
			CodexItem(json: [
				"id": "user",
				"type": "userMessage",
				"content": inputs.map(\.protocolValue),
			])
		)
		let optimisticBody = UserMessagePresenter.body(for: inputs)
		#expect(UserMessagePresenter.body(for: history) == optimisticBody)
		#expect(optimisticBody.contains("2: two\n3: three"))
		#expect(optimisticBody.components(separatedBy: "File reference:").count == 2)
		#expect(optimisticBody.components(separatedBy: "Attached image:").count == 2)
		#expect(!optimisticBody.contains("[Image:"))
		#expect(!optimisticBody.contains("[File reference:"))
	}

	@Test func missingOrEscapingReferencesAreRejectedBeforeSend() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "",
				items: [ComposerContextItem(
					kind: .fileReference,
					title: "Missing",
					path: "missing.swift"
				)],
				project: project
			)
		}
		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "",
				items: [ComposerContextItem(
					kind: .fileReference,
					title: "Outside",
					path: "../outside"
				)],
				project: project
			)
		}
	}

	@Test func symlinkEscapingProjectIsRejected() throws
	{
		let project = try temporaryProject()
		let outside = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
			try? FileManager.default.removeItem(at: outside)
		}
		let source = outside.appendingPathComponent("Outside.swift")
		try "outside".write(
			to: source,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.createSymbolicLink(
			at: project.appendingPathComponent("Linked.swift"),
			withDestinationURL: source
		)

		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "Inspect",
				items: [ComposerContextItem(
					kind: .fileReference,
					title: "Linked.swift",
					path: "Linked.swift"
				)],
				project: project
			)
		}
	}

	@Test func missingImageIsRejected() throws
	{
		let project = try temporaryProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		#expect(throws: ComposerContextError.self)
		{
			try ComposerContextBuilder.inputs(
				text: "Inspect",
				items: [ComposerContextItem(
					kind: .image,
					title: "Missing image",
					path: project.appendingPathComponent("missing.png").path
				)],
				project: project
			)
		}
	}

	private func temporaryProject() throws -> URL
	{
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: url,
			withIntermediateDirectories: true
		)
		return url
	}
}
