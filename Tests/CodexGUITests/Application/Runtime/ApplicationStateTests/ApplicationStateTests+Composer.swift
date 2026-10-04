import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func lateSteeringFailureCannotChangeNextSubmissionOwner() async throws
	{
		let (state, service, project) = try await makeRunningState()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		service.suspendSteer = true
		state.inputs.steer("Old instruction")
		try #require(await waitUntil
		{
			service.pendingSteer != nil
		})
		let completed = makeTurn(
			id: "turn-1",
			status: "completed"
		)
		service.savedTurns = [completed]
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: completed
		))
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		service.nextTurn = makeTurn(
			id: "turn-2",
			status: "inProgress"
		)
		state.inputs.updateDraft("Next request")
		let nextSubmission = try #require(state.inputs.send())
		_ = await nextSubmission.wait()
		service.pendingSteer?.resume(throwing: AppServerError.requestTimedOut("turn/steer"))
		service.pendingSteer = nil
		try #require(await waitUntil
		{
			state.pendingBackendOperationCount == 0
		})
		#expect(state.currentSnapshot.activeExecutionState == .running)
		#expect(state.currentSnapshot.canSteer)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
		#expect(state.currentSnapshot.statusMessage == nil)
	}

	@Test func acknowledgementPreservesDraftEditedAwayAndBackToSubmittedText() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let storage = makeStorage()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		_ = await state.inputs.selectThread(service.thread.id)?.wait()
		try #require(state.currentSnapshot.canSend)
		service.suspendTurnStart = true
		state.inputs.updateDraft("Submitted text")
		let submission = try #require(state.inputs.send())
		try #require(await waitUntil
		{
			service.pendingTurnStart != nil
		})
		state.inputs.updateDraft("Intermediate edit")
		state.inputs.updateDraft("Submitted text")
		service.finishTurnStart(with: service.nextTurn)
		_ = await submission.wait()
		#expect(state.currentSnapshot.draft == "Submitted text")
		try await state.store.awaitAcceptedPersistence()
		#expect(state.currentSnapshot.draft == "Submitted text")
		#expect(storage.draft(
			for: project,
			threadID: service.thread.id
		) == "Submitted text")
	}

	@Test func unboundUncertainNewChatKeepsImageLeaseWithoutReattachingToLaterDraft() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let directory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
		let image = directory.appendingPathComponent("unbound.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let suite = "ComposerUnbound.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: directory)
		)
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		try #require(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		let attachment = ComposerContextItem(
			kind: .image,
			title: "Unbound",
			path: image.path
		)
		state.inputs.updateDraft("Initial uncertain request")
		state.inputs.addDraftContext(attachment)
		service.suspendThreadStart = true
		let submission = try #require(state.inputs.send())
		try #require(await waitUntil
		{
			service.pendingThreadStart != nil
		})
		service.pendingThreadStart?.resume(throwing: AppServerError.requestTimedOut("thread/start"))
		service.pendingThreadStart = nil
		_ = await submission.wait()
		try #require(state.currentSnapshot.taskOutcomeUncertain)
		state.inputs.removeDraftContext(id: attachment.id)
		state.inputs.updateDraft("Later independent draft")
		try #require(await waitUntil
		{
			state.pendingBackendOperationCount == 0
		})
		#expect(state.currentSnapshot.selectedThreadID == nil)
		#expect(state.currentSnapshot.draft == "Later independent draft")
		#expect(state.currentSnapshot.draftContext.isEmpty)
		#expect(storage.draftContext(
			for: project,
			threadID: nil
		).isEmpty)
		#expect(FileManager.default.fileExists(atPath: image.path))
		#expect(state.isTaskActive)
		#expect(!state.currentSnapshot.canSend)
		#expect(state.inputs.send() == nil)
	}

	@Test func uncertainSubmissionRetainsRemovedOwnedImageUntilReconciliation() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let image = imageDirectory.appendingPathComponent("retained.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let suite = "ComposerUncertainty.\(UUID())"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		_ = await state.inputs.selectThread(service.thread.id)?.wait()
		try #require(state.currentSnapshot.canSend)
		let attachment = ComposerContextItem(
			kind: .image,
			title: "Retained",
			path: image.path
		)
		state.inputs.updateDraft("Inspect image")
		state.inputs.addDraftContext(attachment)
		service.startTurnError = AppServerError.requestTimedOut("turn/start")
		_ = await state.inputs.send()?.wait()
		try #require(state.currentSnapshot.taskOutcomeUncertain)
		state.inputs.removeDraftContext(id: attachment.id)
		try #require(await waitUntil
		{
			state.pendingBackendOperationCount == 0
		})
		#expect(FileManager.default.fileExists(atPath: image.path))
		#expect(storage.draftContext(
			for: project,
			threadID: service.thread.id
		).isEmpty)
		service.startTurnError = nil
		_ = await state.inputs.selectThread(service.thread.id)?.wait()
		try #require(await waitUntil
		{
			state.pendingBackendOperationCount == 0
		})
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
		#expect(FileManager.default.fileExists(atPath: image.path))
		#expect(state.currentSnapshot.reusableReferences == [attachment])
		#expect(service.turnStartCount == 1)
	}

	@Test func removingSubmittedImageWaitsForTurnAndSteeringAcknowledgement() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let imageDirectory = project.appendingPathComponent("DraftImages")
		try FileManager.default.createDirectory(
			at: imageDirectory,
			withIntermediateDirectories: true
		)
		let suite = "CodexGUIStateImageTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let storage = LocalStorage(
			defaults: defaults,
			imageStore: DraftImageStore(directory: imageDirectory)
		)
		let service = MockCodexService()
		service.suspendTurnStart = true
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})

		func imageItem(_ title: String) throws -> ComposerContextItem
		{
			let file = imageDirectory.appendingPathComponent("\(UUID().uuidString).png")
			try Data([0x89, 0x50, 0x4e, 0x47]).write(to: file)
			return ComposerContextItem(
				kind: .image,
				title: title,
				path: file.path
			)
		}
		let firstImage = try imageItem("Turn image")
		state.inputs.updateDraft("Inspect the screenshot")
		state.inputs.addDraftContext(firstImage)
		state.inputs.send()
		#expect(await waitUntil
		{
			service.pendingTurnStart != nil
		})
		state.inputs.removeDraftContext(id: firstImage.id)
		#expect(FileManager.default.fileExists(atPath: try #require(firstImage.path)))
		service.finishTurnStart(with: service.nextTurn)
		#expect(await waitUntil
		{
			state.currentSnapshot.reusableReferences == [firstImage]
		})
		#expect(FileManager.default.fileExists(atPath: try #require(firstImage.path)))
		service.emit(.turnStarted(
			threadId: service.thread.id,
			turn: service.nextTurn
		))
		#expect(state.currentSnapshot.canSteer)

		let steeringImage = try imageItem("Steering image")
		service.suspendSteer = true
		state.inputs.updateDraft("Also inspect this")
		state.inputs.addDraftContext(steeringImage)
		state.inputs.steer("Also inspect this")
		#expect(await waitUntil
		{
			service.pendingSteer != nil
		})
		state.inputs.removeDraftContext(id: steeringImage.id)
		#expect(FileManager.default.fileExists(atPath: try #require(steeringImage.path)))
		service.finishPendingSteer(acknowledgedTurnID: service.nextTurn.id)
		#expect(
			await waitUntil
			{
				state.currentSnapshot.reusableReferences == [firstImage, steeringImage]
			}
		)
		#expect(FileManager.default.fileExists(atPath: try #require(steeringImage.path)))
	}

	@Test func firstTurnAcknowledgementDoesNotClearAnotherNewChatDraft() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let image = project.appendingPathComponent("initial.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let service = MockCodexService()
		service.suspendTurnStart = true
		let storage = makeStorage()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		let firstItem = ComposerContextItem(
			kind: .image,
			title: "Initial",
			path: image.path
		)
		state.inputs.updateDraft("Initial request")
		state.inputs.addDraftContext(firstItem)
		let submission = try #require(state.inputs.send())
		#expect(await waitUntil
		{
			service.pendingTurnStart != nil
		})
		#expect(storage.draftContext(
			for: project,
			threadID: service.thread.id
		) == [firstItem])

		state.inputs.newChat()
		let laterItem = ComposerContextItem(
			kind: .textExcerpt,
			title: "Later.swift",
			path: "Later.swift",
			firstLine: 1,
			lastLine: 1,
			excerpt: "let later = true"
		)
		state.inputs.updateDraft("Later request")
		state.inputs.addDraftContext(laterItem)
		service.finishTurnStart(with: service.nextTurn)
		_ = await submission.wait()
		#expect(await waitUntil
		{
			storage.draft(
				for: project,
				threadID: service.thread.id
			).isEmpty
		})
		#expect(state.currentSnapshot.selectedThreadID == nil)
		#expect(state.currentSnapshot.draft == "Later request")
		#expect(state.currentSnapshot.draftContext == [laterItem])
		try await state.store.awaitAcceptedPersistence()
		#expect(storage.draft(
			for: project,
			threadID: service.thread.id
		).isEmpty)
		#expect(storage.draft(
			for: project,
			threadID: nil
		) == "Later request")
		#expect(storage.draftContext(
			for: project,
			threadID: nil
		) == [laterItem])
	}

	@Test func contextDraftSurvivesUncertainSendAndCanBeReusedAfterAcknowledgement() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let image = project.appendingPathComponent("screenshot.png")
		try Data([0x89, 0x50, 0x4e, 0x47]).write(to: image)
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		let imageItem = ComposerContextItem(
			kind: .image,
			title: "Screenshot",
			path: image.path
		)
		state.inputs.updateDraft("Inspect this")
		state.inputs.addDraftContext(imageItem)
		service.startTurnError = AppServerError.requestTimedOut("turn/start")
		state.inputs.send()
		#expect(await waitUntil
		{
			state.currentSnapshot.executionState == .failed
		})
		#expect(state.currentSnapshot.draft == "Inspect this")
		#expect(state.currentSnapshot.draftContext == [imageItem])
		#expect(service.sentInputRequests.count == 1)
		state.inputs.send()
		#expect(service.sentInputRequests.count == 1)

		service.startTurnError = nil
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		state.inputs.send()
		#expect(await waitUntil
		{
			state.currentSnapshot.draftContext.isEmpty
		})
		#expect(service.sentInputRequests.count == 2)
		#expect(service.sentInputRequests[1].last == .localImage(path: image.path))
		#expect(state.currentSnapshot.reusableReferences == [imageItem])
		state.inputs.reuseReference(id: imageItem.id)
		#expect(state.currentSnapshot.draftContext.count == 1)
		#expect(state.currentSnapshot.draftContext.first?.id != imageItem.id)
	}

	@Test func uncertainSendKeepsDraftAndBlocksResendUntilConversationIsRead() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			service.readThreadCount == 1
		})

		state.inputs.updateDraft("Change README")
		service.startTurnError = AppServerError.requestTimedOut("turn/start")
		state.inputs.send()
		#expect(await waitUntil
		{
			state.currentSnapshot.executionState == .failed
		})
		#expect(service.turnStartCount == 1)
		#expect(state.currentSnapshot.draft == "Change README")
		#expect(state.currentSnapshot.taskOutcomeUncertain)
		#expect(!state.currentSnapshot.canSend)

		state.inputs.send()
		#expect(service.turnStartCount == 1)

		let lateTurn = makeTurn(
			id: "late-turn",
			status: "completed"
		)
		service.savedTurns = [lateTurn]
		service.emit(
			.turnStarted(
				threadId: service.thread.id,
				turn: makeTurn(
					id: "late-turn",
					status: "inProgress"
				)
			)
		)
		#expect(state.currentSnapshot.executionState == .failed)
		service.emit(.turnCompleted(
			threadId: service.thread.id,
			turn: lateTurn
		))
		#expect(state.currentSnapshot.executionState == .failed)
		#expect(!state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.draft == "Change README")
		state.inputs.send()
		#expect(service.turnStartCount == 1)

		service.readThreadError = AppServerError.protocolError("Temporary read failure")
		await state.inputs.connect()
		#expect(!state.currentSnapshot.canSend)
		#expect(state.currentSnapshot.statusMessage?.contains("Could not check") == true)

		service.readThreadError = nil
		state.inputs.refreshThreads()
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		#expect(service.turnStartCount == 1)
		#expect(state.currentSnapshot.draft == "Change README")
		#expect(state.currentSnapshot.statusMessage?.contains("Review the saved draft") == true)
		#expect(!state.currentSnapshot.taskOutcomeUncertain)
	}

	@Test func startupRestoresSelectedThreadAndItsDraftBeforeReconciliation() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let storage = makeStorage()
		storage.rememberProject(project)
		storage.saveSelectedThreadID(
			"thread-1",
			for: project
		)
		storage.saveDraft(
			"unsent thread draft",
			for: project,
			threadID: "thread-1"
		)
		storage.saveDraft(
			"new chat draft",
			for: project,
			threadID: nil
		)
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)

		#expect(state.currentSnapshot.selectedThreadID == "thread-1")
		#expect(state.currentSnapshot.draft == "unsent thread draft")
		#expect(!state.currentSnapshot.canSend)
		await state.inputs.connect()
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		#expect(service.readThreadCount == 1)
		#expect(state.currentSnapshot.draft == "unsent thread draft")

		state.inputs.newChat()
		#expect(storage.selectedThreadID(for: project) == nil)
		#expect(state.currentSnapshot.draft == "new chat draft")
		#expect(storage.draft(
			for: project,
			threadID: "thread-1"
		) == "unsent thread draft")
	}

	@Test func archiveClearsSelectionButKeepsDraftAndUnarchiveReturnsToActiveList() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let storage = makeStorage()
		let service = MockCodexService()
		let state = WorkspaceTestFixture(
			server: service,
			storage: storage
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canManageThreads
		})
		state.inputs.updateDraft("saved in thread")

		state.inputs.archiveSelectedThread()
		#expect(
			await waitUntil
			{
				service.archivedThreadIDs == [service.thread.id]
					&& state.currentSnapshot.selectedThreadID == nil
			}
		)
		#expect(storage.selectedThreadID(for: project) == nil)
		try await state.store.awaitAcceptedPersistence()
		#expect(storage.draft(
			for: project,
			threadID: service.thread.id
		) == "saved in thread")

		state.inputs.setArchivedFilter(true)
		#expect(
			await waitUntil
			{
				state.currentSnapshot.showingArchived
					&& state.currentSnapshot.threads.map(\.id) == [service.thread.id]
			}
		)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canManageThreads
		})
		#expect(!state.currentSnapshot.canSend)
		state.inputs.archiveSelectedThread()
		#expect(
			await waitUntil
			{
				service.unarchivedThreadIDs == [service.thread.id]
					&& !state.currentSnapshot.showingArchived && state.currentSnapshot
					.canManageThreads
			}
		)
		#expect(storage.selectedThreadID(for: project) == service.thread.id)
		#expect(state.currentSnapshot.draft == "saved in thread")
	}

	@Test func lateTurnStartAfterDisconnectDoesNotClearDraftOrResumeTask() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		service.suspendTurnStart = true
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage()
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canSend
		})
		state.inputs.updateDraft("Write a change")
		let submission = try #require(state.inputs.send())
		#expect(await waitUntil
		{
			service.pendingTurnStart != nil
		})

		service.emitDisconnect("Backend exited.")
		#expect(state.currentSnapshot.executionState == .disconnected)
		#expect(state.currentSnapshot.draft == "Write a change")

		service.finishTurnStart(with: makeTurn(
			id: "late-turn",
			status: "inProgress"
		))
		_ = await submission.wait()
		#expect(state.currentSnapshot.executionState == .disconnected)
		#expect(state.currentSnapshot.draft == "Write a change")
		state.inputs.send()
		#expect(service.turnStartCount == 1)
	}

	@Test func sendIncludesOnlySelectedContextAndInvokesCurrentSkill() async throws
	{
		let project = try makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let contextDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
			"CodexGUIContextTests-\(UUID().uuidString)",
			isDirectory: true
		)
		defer
		{
			try? FileManager.default.removeItem(at: contextDirectory)
		}
		let service = MockCodexService()
		service.availableSkills = [
			AvailableSkill(json: [
				"name": "review",
				"description": "Review changes",
				"path": "/skills/review/SKILL.md",
				"scope": "repo",
				"enabled": true,
			])!
		]
		let state = WorkspaceTestFixture(
			server: service,
			storage: makeStorage(),
			projectContextStore: ProjectContextStore(directory: contextDirectory)
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(
			await waitUntil
			{
				state.currentSnapshot.canSend && state.currentSnapshot.skillCatalog != nil
			}
		)
		var context = ProjectContext()
		context.items = [
			ProjectContextItem(
				kind: .note,
				title: "Include",
				body: "chosen detail",
				isIncluded: true
			),
			ProjectContextItem(
				kind: .decision,
				title: "Exclude",
				body: "private detail"
			),
		]
		context.savedPrompts = [SavedPrompt(
			title: "Inspect only",
			instructions: "do not add"
		)]
		context.selectedPromptID = context.savedPrompts[0].id
		context.selectedSkill = ProjectSkillSelection(
			name: "review",
			description: "Review changes",
			path: "/old/path"
		)
		state.inputs.updateProjectContext(context)
		state.inputs.updateDraft("Check this")
		state.inputs.send()
		#expect(await waitUntil
		{
			service.sentTurnRequests.count == 1
		})
		let request = service.sentTurnRequests[0]
		#expect(request.text.contains("Check this"))
		#expect(request.text.contains("chosen detail"))
		#expect(!request.text.contains("private detail"))
		#expect(!request.text.contains("do not add"))
		#expect(request.skills == [SkillReference(
			name: "review",
			path: "/skills/review/SKILL.md"
		)])
	}
}
