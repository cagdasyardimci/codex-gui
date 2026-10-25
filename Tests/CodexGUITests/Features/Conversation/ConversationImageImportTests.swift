import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct ConversationImageImportTests
{
	@Test func pendingImportBlocksSubmissionAndRestoresControlsAfterDelivery() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		let controller = makeController(
			directory: directory,
			gate: gate
		)
		var sends = 0
		var steered: [String] = []
		controller.onSend =
		{
			sends += 1
		}
		controller.onSteer =
		{
			steered.append($0)
		}
		controller.onImportImageContext =
		{
			_ in true
		}
		#expect(controller.sendButton.isEnabled)
		controller.attachImage(
			.data(try DraftImageImportTestFixture.png()),
			title: "Pending image"
		)
		let pending = try lastImport(controller)
		let started = await gate.waitUntilStarted()
		try #require(started)
		#expect(!controller.sendButton.isEnabled)
		#expect(!controller.steerButton.isEnabled)
		#expect(controller.composer.isEditable)
		controller.perform(NSSelectorFromString("send"))
		controller.perform(NSSelectorFromString("steer"))
		#expect(sends == 0)
		#expect(steered.isEmpty)
		gate.release()
		await pending.value
		#expect(controller.sendButton.isEnabled)
		#expect(controller.steerButton.isEnabled)
		controller.perform(NSSelectorFromString("send"))
		controller.perform(NSSelectorFromString("steer"))
		#expect(sends == 1)
		#expect(steered == ["Existing draft"])
	}

	@Test func repeatedImportsRetainFIFOAndCapturedReceivers() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		let controller = makeController(
			directory: directory,
			gate: gate
		)
		var retained: [ComposerContextItem] = []
		controller.onImportImageContext =
		{
			retained.append($0)
			return true
		}
		let png = try DraftImageImportTestFixture.png()
		let firstTitle = "First 🐈\u{2028} image"
		controller.attachImage(
			.data(png),
			title: firstTitle
		)
		let started = await gate.waitUntilStarted()
		try #require(started)
		controller.attachImage(
			.data(png),
			title: "Second image"
		)
		let last = try lastImport(controller)
		#expect(gate.preparationCount == 1)
		controller.onImportImageContext =
		{
			_ in
			Issue.record("An import used the replacement receiver.")
			return false
		}
		gate.release()
		await last.value
		#expect(retained.map(\.title) == [firstTitle, "Second image"])
		#expect(retained.allSatisfy
		{
			$0.kind == .image && $0.path.map
			{
				FileManager.default.fileExists(atPath: $0)
			} == true
		})
		#expect(controller.imageImportTasks.isEmpty)
		#expect(controller.lastImageImportID == nil)
	}

	@Test func rejectedImportDeletesGeneratedCopyAndPreservesOriginalFile() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let copies = directory.appendingPathComponent("copies")
		let original = directory.appendingPathComponent("Original 🐈.png")
		let png = try DraftImageImportTestFixture.png()
		try await BackgroundTestWork.perform
		{
			try png.write(to: original)
		}
		let controller = makeController(directory: copies)
		var rejected: ComposerContextItem?
		controller.onImportImageContext =
		{
			rejected = $0
			return false
		}
		controller.attachImage(
			.file(original),
			title: original.lastPathComponent
		)
		try await lastImport(controller).value
		let item = try #require(rejected)
		let path = try #require(item.path)
		#expect(item.title == original.lastPathComponent)
		#expect(!FileManager.default.fileExists(atPath: path))
		#expect(FileManager.default.fileExists(atPath: original.path))
		#expect(DraftImageImportTestFixture.generatedImages(in: copies).isEmpty)
	}

	@Test func samePathConversationABARetiresPreparingAndQueuedImports() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		let controller = makeController(
			directory: directory,
			gate: gate
		)
		var retained: [ComposerContextItem] = []
		controller.onImportImageContext =
		{
			retained.append($0)
			return true
		}
		let png = try DraftImageImportTestFixture.png()
		controller.attachImage(
			.data(png),
			title: "Preparing"
		)
		let started = await gate.waitUntilStarted()
		try #require(started)
		controller.attachImage(
			.data(png),
			title: "Queued"
		)
		let pending = Array(controller.imageImportTasks.values)
		controller.render(snapshot(threadID: "B"))
		controller.render(snapshot(threadID: "A"))
		gate.release()
		for task in pending
		{
			await task.value
		}
		#expect(retained.isEmpty)
		#expect(gate.preparationCount == 1)
		#expect(DraftImageImportTestFixture.generatedImages(in: directory).isEmpty)
		controller.attachImage(
			.data(png),
			title: "Current A"
		)
		try await lastImport(controller).value
		#expect(retained.map(\.title) == ["Current A"])
	}

	@Test func sameOwnerNewDraftLifetimeCancelsPendingImport() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		let controller = makeController(
			directory: directory,
			gate: gate
		)
		controller.onImportImageContext =
		{
			_ in
			Issue.record("A retired draft received an image.")
			return true
		}
		controller.attachImage(
			.data(try DraftImageImportTestFixture.png()),
			title: "Old draft"
		)
		let pending = try lastImport(controller)
		let started = await gate.waitUntilStarted()
		try #require(started)
		let previousGeneration = controller.selectionGeneration
		controller.render(snapshot(draftLifetime: 1))
		#expect(controller.selectionGeneration == previousGeneration + 1)
		gate.release()
		await pending.value
		#expect(DraftImageImportTestFixture.generatedImages(in: directory).isEmpty)
	}

	@Test func acceptanceMayChangeOwnerWithoutDeletingRetainedCopy() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let controller = makeController(directory: directory)
		var retained: ComposerContextItem?
		controller.onImportImageContext =
		{
			item in
			retained = item
			controller.render(snapshot(threadID: "B"))
			return true
		}
		controller.attachImage(
			.data(try DraftImageImportTestFixture.png()),
			title: "Retained before switching"
		)
		try await lastImport(controller).value
		let path = try #require(retained?.path)
		#expect(FileManager.default.fileExists(atPath: path))
		#expect(controller.imageImportTasks.isEmpty)
		controller.onImportImageContext = nil
	}

	@Test func controllerRetirementCancelsWorkerWithoutRetainingView() async throws
	{
		let directory = try await BackgroundTestWork.perform
		{
			try DraftImageImportTestFixture.temporaryDirectory()
		}
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let gate = DraftImageImportTestGate()
		defer
		{
			gate.release()
		}
		var controller: ConversationViewController? = ConversationViewController()
		controller?.draftImageStore = DraftImageStore(
			directory: directory,
			preparePNG: gate.prepare
		)
		controller?.onImportImageContext =
		{
			_ in
			Issue.record("A retired controller delivered an image.")
			return true
		}
		controller?.attachImage(
			.data(try DraftImageImportTestFixture.png()),
			title: "Pending"
		)
		let pending = try lastImport(try #require(controller))
		let started = await gate.waitUntilStarted()
		try #require(started)
		let isControllerReleased =
		{
			[weak controller] in controller == nil
		}
		controller = nil
		#expect(isControllerReleased())
		gate.release()
		await pending.value
		#expect(DraftImageImportTestFixture.generatedImages(in: directory).isEmpty)
	}

	private func makeController(
		directory: URL,
		gate: DraftImageImportTestGate? = nil
	) -> ConversationViewController
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		controller.draftImageStore = DraftImageStore(
			directory: directory,
			preparePNG:
			{
				source in
				if let gate
				{
					return try gate.prepare(source)
				}
				return try source.pngData()
			}
		)
		controller.render(snapshot())
		return controller
	}

	private func lastImport(_ controller: ConversationViewController) throws -> Task<Void, Never>
	{
		let requestID = try #require(controller.lastImageImportID)
		return try #require(controller.imageImportTasks[requestID])
	}

	private func snapshot(
		threadID: String = "A",
		draftLifetime: Int = 0
	) -> ConversationSnapshot
	{
		var snapshot = ConversationSnapshot(
			projectPath: nil,
			threads: [],
			selectedThreadID: threadID,
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "Existing draft",
			canSend: true,
			accountDescription: "Mock",
			backendDescription: "Mock",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		snapshot.composerDraftLifetime = draftLifetime
		snapshot.canSteer = true
		return snapshot
	}
}
