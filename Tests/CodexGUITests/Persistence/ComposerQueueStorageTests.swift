import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct ComposerQueueStorageTests
{
	@Test func queueMigrationAndEditRestorationRetainImagesUntilTheirLastReferenceIsRemoved() throws
	{
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent(UUID().uuidString)
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let isolated = try IsolatedUserDefaultsFixture(prefix: "ComposerQueueStorageTests")
		defer
		{
			isolated.cleanup()
		}
		let images = DraftImageStore(directory: directory)
		let image = NSImage(
			cgImage: try DraftImageImportTestFixture.image(),
			size: NSSize(
				width: 3,
				height: 2
			)
		)
		let item = try images.importImage(image)
		let path = try #require(item.path)
		let project = URL(fileURLWithPath: "/tmp/queued-project")
		let storage = LocalStorage(
			defaults: isolated.defaults,
			imageStore: images
		)
		let message = QueuedComposerMessage(
			id: UUID(),
			text: "Inspect image",
			context: [item],
			modelID: "captured-model",
			effort: "high",
			preferences: .standard,
			skills: [],
			collaborationMode: nil,
			serviceTier: nil
		)
		storage.saveDraftContext(
			[item],
			for: project,
			threadID: "chat"
		)
		storage.saveQueuedMessages(
			[message],
			for: project,
			threadID: "chat"
		)
		storage.saveDraftContext(
			[],
			for: project,
			threadID: "chat"
		)
		#expect(FileManager.default.fileExists(atPath: path))
		let restored = LocalStorage(
			defaults: isolated.defaults,
			imageStore: images
		)
		#expect(restored.queuedMessages(
			for: project,
			threadID: "chat"
		) == [message])
		#expect(restored.queuedMessages(
			for: project,
			threadID: "other"
		).isEmpty)
		#expect(restored.queuedMessages(
			for: URL(fileURLWithPath: "/tmp/other-project"),
			threadID: "chat"
		).isEmpty)
		isolated.defaults.set(
			[project.path: ["thread:chat": try JSONEncoder().encode([message])]],
			forKey: "CodexGUI.queuedMessages"
		)
		#expect(restored.queuedMessages(
			for: project,
			threadID: "chat"
		) == [message])
		#expect(restored.queuedMessageEdit(
			for: project,
			threadID: "chat"
		) == nil)
		let edit = QueuedComposerEdit(
			message: message,
			position: 0
		)
		restored.saveQueuedMessages(
			[],
			for: project,
			threadID: "chat",
			editing: edit
		)
		#expect(FileManager.default.fileExists(atPath: path))
		let editingStorage = LocalStorage(
			defaults: isolated.defaults,
			imageStore: images
		)
		#expect(editingStorage.queuedMessageEdit(
			for: project,
			threadID: "chat"
		) == edit)
		#expect(editingStorage.queuedMessages(
			for: project,
			threadID: "chat"
		).isEmpty)
		editingStorage.saveQueuedMessages(
			[],
			for: project,
			threadID: "chat"
		)
		#expect(!FileManager.default.fileExists(atPath: path))
	}
}
