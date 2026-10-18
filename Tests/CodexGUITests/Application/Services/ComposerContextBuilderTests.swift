import Foundation
import Testing

@testable import CodexGUI

@Suite
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
		#expect(!optimisticBody.contains("Attached image:"))
		#expect(history.text?.contains("Attached image: Screenshot") == true)
		#expect(UserMessagePresenter.imageAttachments(for: inputs).map(\.path) == [image.path])
		#expect(!optimisticBody.contains("[Image:"))
		#expect(!optimisticBody.contains("[File reference:"))
	}

	@Test func absoluteAndRelativeReferencesNormalizeToTheSameSubmission() throws
	{
		let project = try temporaryProject().resolvingSymlinksInPath()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let source = project.appendingPathComponent("README.md")
		try Data("intended".utf8).write(to: source)
		// The old absolute-path join could silently choose this different nested file.
		let nested = project.appendingPathComponent(source.path)
		try FileManager.default.createDirectory(
			at: nested.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try Data("different".utf8).write(to: nested)
		for path in ["README.md", source.path, "./README.md"]
		{
			let inputs = try ComposerContextBuilder.inputs(
				text: "Inspect",
				items: [ComposerContextItem(
					kind: .fileReference,
					title: "README.md",
					path: path
				)],
				project: project
			)
			#expect(inputs == [
				.text("Inspect\n\nFile reference: README.md"),
				.mention(
					name: "README.md",
					path: source.path
				),
			])
		}
	}

	@Test func absoluteOutsideAndPrefixSiblingReferencesAreRejected() throws
	{
		let project = try temporaryProject()
		let sibling = URL(fileURLWithPath: project.path + "-other")
		try FileManager.default.createDirectory(
			at: sibling,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: project)
			try? FileManager.default.removeItem(at: sibling)
		}
		let file = sibling.appendingPathComponent("outside.txt")
		try Data("outside".utf8).write(to: file)
		for path in [file.path, file.path + "\0suffix"]
		{
			#expect(throws: ComposerContextError.self)
			{
				try ComposerContextBuilder.inputs(
					text: "Inspect",
					items: [ComposerContextItem(
						kind: .fileReference,
						title: "outside",
						path: path
					)],
					project: project
				)
			}
		}
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

	@Test(arguments: ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"])
	func preparedExcerptPreservesLineBoundsAndBlankLines(separator: String) throws
	{
		let cases: [(first: Int?, last: Int?, expected: String)] = [
			(nil, nil, "Selected code from Example.swift, lines 1–3:\n1: \n2: value\n3: "),
			(4, nil, "Selected code from Example.swift, lines 4–6:\n4: \n5: value\n6: "),
			(nil, 3, "Selected code from Example.swift, lines 1–3:\n1: \n2: value\n3: "),
			(4, 6, "Selected code from Example.swift, lines 4–6:\n4: \n5: value\n6: ")
		]
		for value in cases
		{
			var model = WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(),
				canonicalCheckoutPath: "/project"
			))
			model.connection.generation = 1
			model.connection.isConnected = true
			model.execution.state = .ready
			model.composer.drafts[.newChat] = ComposerDraft(
				text: "request",
				revision: 1
			)
			let item = ComposerContextItem(
				kind: .textExcerpt,
				title: "Example.swift",
				path: "Example.swift",
				firstLine: value.first,
				lastLine: value.last,
				excerpt: separator + "value" + separator
			)
			model.composer.drafts[.newChat]?.context = [item]
			let draft = model.composer.drafts[.newChat] ?? ComposerDraft()
			let captured = ComposerSubmission(
				context: OperationContext(
					workspace: model.identity,
					generation: model.connection.generation,
					requestID: UUID()
				),
				conversation: .newChat,
				draft: draft,
				inputs: [.text(draft.text)],
				skills: [],
				modelID: nil,
				effort: nil,
				preferences: .standard,
				retainedContextRequestID: UUID(),
				projectContextRevision: 0
			)
			let inputs = try ComposerContextBuilder.inputs(
				text: captured.draft.text,
				items: captured.draft.context,
				project: URL(fileURLWithPath: "/project")
			)
			#expect(inputs == [.text("request\n\n" + value.expected)])
			let prepared = ComposerSubmission(
				context: captured.context,
				conversation: captured.conversation,
				draft: captured.draft,
				inputs: inputs,
				skills: captured.skills,
				modelID: captured.modelID,
				effort: captured.effort,
				preferences: captured.preferences,
				retainedContextRequestID: captured.retainedContextRequestID,
				projectContextRevision: 0
			)
			#expect(WorkspaceEligibility(model: model).acceptsSubmission(prepared))
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
