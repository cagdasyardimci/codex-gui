import Foundation

@testable import CodexGUI

@MainActor
struct CapturedIntentStoreFixture
{
	let store: WorkspaceStateStore
	let service: WorkspaceCodexService
	private let root: URL
	private let project: URL
	private let contexts: ProjectContextStore
	private let defaults: IsolatedUserDefaultsFixture
	private let ownsRoot: Bool

	/// Sharing retains overlapping checkout identity; clean the original fixture after its peers.
	static func makeStore(
		threadID: String = "thread",
		sharing fixture: Self? = nil
	) async throws -> Self
	{
		let root: URL
		let project: URL
		let contexts: ProjectContextStore
		if let fixture
		{
			root = fixture.root
			project = fixture.project
			contexts = fixture.contexts
		}
		else
		{
			// A native conversation eagerly indexes its checkout.
			// Use a small owned project instead of the entire host temp directory.
			root = try await BackgroundTestWork.perform
			{
				let root = FileManager.default.temporaryDirectory
					.appendingPathComponent(
						"WorkspaceIntent-\(UUID().uuidString)",
						isDirectory: true
					)
					.standardizedFileURL.resolvingSymlinksInPath()
				do
				{
					try FileManager.default.createDirectory(
						at: root.appendingPathComponent("checkout"),
						withIntermediateDirectories: true
					)
				}
				catch
				{
					try? FileManager.default.removeItem(at: root)
					throw error
				}
				return root
			}
			project = root.appendingPathComponent("checkout")
			contexts = ProjectContextStore(directory: root.appendingPathComponent("contexts"))
		}
		let defaults: IsolatedUserDefaultsFixture
		do
		{
			defaults = try IsolatedUserDefaultsFixture(prefix: "WorkspaceIntent")
		}
		catch
		{
			if fixture == nil
			{
				try? FileManager.default.removeItem(at: root)
			}
			throw error
		}
		let service = WorkspaceCodexService(
			directory: project,
			threadID: threadID
		)
		let identity = WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: project.path
		)
		let reference = WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: identity.sessionID),
			workspace: identity
		)
		let store = WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(reference: reference),
			dependencies: WorkspaceStoreDependencies(
				service: service,
				storage: LocalStorage(defaults: defaults.defaults),
				projectContextStore: contexts
			)
		)
		return Self(
			store: store,
			service: service,
			root: root,
			project: project,
			contexts: contexts,
			defaults: defaults,
			ownsRoot: fixture == nil
		)
	}

	func cleanup()
	{
		store.shutdown()
		defaults.cleanup()
		if ownsRoot
		{
			try? FileManager.default.removeItem(at: root)
		}
	}
}
