import Foundation

@testable import CodexGUI

@MainActor
enum WorkspaceStoreFactoryFixture
{
	static func make(
		publicationWait: @escaping @MainActor () async -> Void =
		{
		}
	) -> (WorkspaceStateStore, WorkspaceCodexService, LocalStorage, UserDefaults, String)
	{
		let suite = "WorkspaceFactory.\(UUID())"
		let defaults = UserDefaults(suiteName: suite)!
		let storage = LocalStorage(defaults: defaults)
		let directory = URL(fileURLWithPath: "/tmp")
		storage.saveSelectedThreadID(
			"factory-thread",
			for: directory
		)
		storage.saveDraft(
			"Persisted draft",
			for: directory,
			threadID: "factory-thread"
		)
		let service = WorkspaceCodexService(
			directory: directory,
			threadID: "factory-thread"
		)
		let session = UUID()
		let configuration = WorkspaceStoreConfiguration(reference: WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: session),
			workspace: WorkspaceIdentity(
				sessionID: session,
				canonicalCheckoutPath: "/private/tmp"
			)
		))
		let contextDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("FactoryContext-\(UUID())")
		let store = WorkspaceStoreFactory.make(
			configuration: configuration,
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: storage,
				projectContextStore: ProjectContextStore(directory: contextDirectory),
				publicationWait: publicationWait
			)
		)
		return (store, service, storage, defaults, suite)
	}
}
