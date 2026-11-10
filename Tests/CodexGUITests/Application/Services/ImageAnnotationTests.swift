import Foundation
import Testing

@testable import CodexGUI

struct ImageAnnotationTests
{
	@Test func multipleImagesKeepTheirOwnCommentsAndAttachmentOrder() throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let paths = ["dark.png", "white.png"].map
		{
			directory.appendingPathComponent($0).path
		}
		for path in paths
		{
			try Data([1]).write(to: URL(fileURLWithPath: path))
		}
		let first = ComposerContextItem(
			kind: .image,
			title: "Dark",
			path: paths[0]
		)
		let annotation = ImageAnnotation(
			x: 0.49,
			y: 0.448,
			text: "image-2"
		)
		let second = ComposerContextItem(
			kind: .image,
			title: "White",
			path: paths[1],
			imageAnnotations: [annotation]
		)
		let items = [first, second]
		let input = try ComposerContextBuilder.inputs(
			text: "Inspect",
			items: items,
			project: directory
		)
		#expect(input == [
			.text("Inspect\n\nImage 2:\n1. (x: 49%, y: 44.8%) image-2"),
			.localImage(path: paths[0]),
			.localImage(path: paths[1])
		])
		let reversed = try ComposerContextBuilder.inputs(
			text: "",
			items: [second, first],
			project: directory
		)
		#expect(reversed.first == .text("Image 1:\n1. (x: 49%, y: 44.8%) image-2"))
		let encoded = try JSONEncoder().encode(items)
		#expect(try JSONDecoder().decode(
			[ComposerContextItem].self,
			from: encoded
		) == items)
		#expect(second.reused().imageAnnotations == [annotation])
	}

	@MainActor
	@Test func annotationOnlyChangesSurviveDraftStorageReload() throws
	{
		let isolated = try IsolatedUserDefaultsFixture(prefix: "ImageAnnotationStorage")
		defer
		{
			isolated.cleanup()
		}
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let image = directory.appendingPathComponent("image.png")
		try Data([1]).write(to: image)
		var item = ComposerContextItem(
			kind: .image,
			title: "Image",
			path: image.path
		)
		let storage = LocalStorage(defaults: isolated.defaults)
		storage.saveDraftContext(
			[item],
			for: directory,
			threadID: "chat"
		)
		item.imageAnnotations = [ImageAnnotation(
			x: 0,
			y: 1,
			text: "Bottom left"
		)]
		storage.saveDraftContext(
			[item],
			for: directory,
			threadID: "chat"
		)
		let reopened = LocalStorage(defaults: isolated.defaults)
		#expect(reopened.draftContext(
			for: directory,
			threadID: "chat"
		) == [item])
		item.imageAnnotations = nil
		reopened.saveDraftContext(
			[item],
			for: directory,
			threadID: "chat"
		)
		#expect(LocalStorage(defaults: isolated.defaults).draftContext(
			for: directory,
			threadID: "chat"
		) == [item])
	}

	@Test func olderDraftsDecodeWithoutAnnotations() throws
	{
		let data = Data(#"{"id":"legacy","kind":"image","title":"Image","path":"/tmp/image.png"}"#
			.utf8)
		let item = try JSONDecoder().decode(
			ComposerContextItem.self,
			from: data
		)
		#expect(item.imageAnnotations == nil)
	}

	@MainActor
	@Test func savesOnlyTheTargetImageAndRejectsStaleOrInvalidUpdates() throws
	{
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: "/tmp/comments"
		)
		var model = WorkspaceModel(identity: identity)
		model.connection.generation = 1
		let conversation = ConversationKey.thread("thread")
		let first = ComposerContextItem(
			kind: .image,
			title: "First",
			path: "/tmp/first.png"
		)
		let second = ComposerContextItem(
			kind: .image,
			title: "Second",
			path: "/tmp/second.png"
		)
		model.composer.drafts[conversation] = ComposerDraft(
			text: "Keep this text",
			context: [first, second],
			revision: 1
		)
		let context = OperationContext(
			workspace: identity,
			generation: 1,
			requestID: UUID(),
			threadID: "thread"
		)
		let annotation = ImageAnnotation(
			x: 0.996,
			y: 0.94,
			text: "Bottom right"
		)
		let result = ComposerReducer.reduce(
			&model,
			.composer(.imageAnnotationsSaved(
				context,
				conversation: conversation,
				itemID: second.id,
				annotations: [annotation],
				revision: 2
			))
		)
		let saved = try #require(model.composer.drafts[conversation])
		#expect(saved.context[0] == first)
		#expect(saved.context[1].imageAnnotations == [annotation])
		#expect(saved.text == "Keep this text")
		#expect(!result.effects.isEmpty)
		for (id, annotations, revision) in [
			(first.id, [annotation], 2),
			("removed-image", [annotation], 3),
			(first.id, [ImageAnnotation(
				x: -1,
				y: 0,
				text: "Invalid"
			)], 3)
		]
		{
			_ = ComposerReducer.reduce(
				&model,
				.composer(.imageAnnotationsSaved(
					context,
					conversation: conversation,
					itemID: id,
					annotations: annotations,
					revision: revision
				))
			)
			#expect(model.composer.drafts[conversation] == saved)
		}
	}
}
