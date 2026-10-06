import Foundation

@testable import CodexGUI

@MainActor
enum CapturedIntentStoreFixture
{
	static func makeStore(threadID: String = "thread")
		-> (WorkspaceStateStore, WorkspaceCodexService)
	{
		let path = FileManager.default.temporaryDirectory.standardizedFileURL.path
		let service = WorkspaceCodexService(
			directory: URL(fileURLWithPath: path),
			threadID: threadID
		)
		let session = UUID()
		let identity = WorkspaceIdentity(
			sessionID: session,
			canonicalCheckoutPath: path
		)
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: session),
			workspace: identity
		)
		let storage = LocalStorage(defaults: UserDefaults(suiteName: "WorkspaceIntent.\(UUID())")!)
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(reference: reference),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: storage
			)
		)
		return (store, service)
	}
}
