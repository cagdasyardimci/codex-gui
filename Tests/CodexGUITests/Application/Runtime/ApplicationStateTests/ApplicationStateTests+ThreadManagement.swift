import Foundation
import Testing

@testable import CodexGUI

extension ApplicationStateTests
{
	@Test func renamingSelectedThreadCallsServiceAndReleasesManagementLock() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let service = MockCodexService()
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let state = WorkspaceTestFixture(
			server: service,
			storage: LocalStorage(defaults: defaultsFixture.defaults)
		)
		await state.inputs.connect()
		service.configureCheckout(project)
		state.inputs.openProject(project)
		state.inputs.selectThread(service.thread.id)
		#expect(await waitUntil
		{
			state.currentSnapshot.canManageThreads
		})

		state.inputs.renameSelectedThread("  Clear name  ")
		#expect(!state.currentSnapshot.canManageThreads)
		#expect(
			await waitUntil
			{
				service.renamedThreads.count == 1
					&& state.currentSnapshot.canManageThreads
			}
		)
		#expect(service.renamedThreads.first?.0 == service.thread.id)
		#expect(service.renamedThreads.first?.1 == "Clear name")
	}

	@Test func archiveClearsSelectionButKeepsDraftAndUnarchiveReturnsToActiveList() async throws
	{
		let project = try await makeProject()
		defer
		{
			try? FileManager.default.removeItem(at: project)
		}
		let defaultsFixture = try IsolatedUserDefaultsFixture(prefix: "CodexGUIStateTests")
		defer
		{
			defaultsFixture.cleanup()
		}
		let storage = LocalStorage(defaults: defaultsFixture.defaults)
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
}
