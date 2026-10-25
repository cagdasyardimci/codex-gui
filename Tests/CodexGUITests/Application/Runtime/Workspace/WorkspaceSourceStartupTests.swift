import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct WorkspaceSourceStartupTests
{

	@Test("Source startup preserves a corrupt project context and exposes its load failure")
	func corruptContextIsUntouched() async throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		let project = try fixture.project("corrupt")
		fixture.storage.rememberProject(project)
		let path = fixture.contexts.fileURL(for: project)
		try FileManager.default.createDirectory(
			at: path.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		let bytes = Data("corrupt project context".utf8)
		try bytes.write(to: path)
		let store = fixture.makeStore()
		defer
		{
			store.shutdown()
		}
		store.dispatch(.workspaceLifecycle(.sourceStartupRequested(store.operationContext())))
		#expect(store.model.identity.canonicalCheckoutPath == project.path)
		let load = try #require(store.model.contextNavigation.pendingContextLoad)
		let handle = try #require(store.operation(for: load.context))
		_ = await handle.wait()
		#expect(store.currentSnapshot.projectContextError != nil)
		#expect(try Data(contentsOf: path) == bytes)
	}

	@Test("Only the exact source startup ticket, session and generation can activate a checkout")
	func obsoleteAndForeignResultsAreRejected()
	{
		var model = WorkspaceModel(identity: WorkspaceIdentity(
			sessionID: UUID(),
			canonicalCheckoutPath: nil
		))
		let first = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		let current = OperationContext(
			workspace: model.identity,
			generation: 0,
			requestID: UUID()
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.sourceStartupRequested(first))
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.sourceStartupRequested(current))
		)
		let preferences = PreferencesRestoration(
			modelPreference: nil,
			runPreferences: .standard,
			recentProjects: [],
			pinnedProjectPaths: [],
			projectDisplayNames: [:]
		)
		let project = WorkspaceProjectOpening(
			identity: WorkspaceIdentity(
				sessionID: model.identity.sessionID,
				canonicalCheckoutPath: "/captured"
			),
			selectedThreadID: "thread"
		)
		let startup = WorkspaceSourceStartup(
			project: project,
			pendingCommands: [],
			preferences: preferences
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.sourceStartupRestored(
				first,
				.succeeded(startup)
			))
		)
		#expect(model.identity.canonicalCheckoutPath == nil)
		#expect(model.lifecycle.pendingSourceStartup == current)
		let foreign = WorkspaceSourceStartup(
			project: WorkspaceProjectOpening(
				identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: "/foreign"
				),
				selectedThreadID: nil
			),
			pendingCommands: [],
			preferences: preferences
		)
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.sourceStartupRestored(
				current,
				.succeeded(foreign)
			))
		)
		#expect(model.identity.canonicalCheckoutPath == nil)
		#expect(model.lifecycle.pendingSourceStartup == current)
		model.connection.generation = 1
		_ = WorkspaceLifecycleReducer.reduce(
			&model,
			.workspaceLifecycle(.sourceStartupRestored(
				current,
				.succeeded(startup)
			))
		)
		#expect(model.identity.canonicalCheckoutPath == nil)
		_ = WorkspaceLifecycleComposition.reduceDomainEvent(
			&model,
			.connectionBegan,
			context: OperationContext(
				workspace: model.identity,
				generation: 1,
				requestID: UUID()
			)
		)
		#expect(model.lifecycle.pendingSourceStartup == nil)
	}
}

@MainActor
private struct SourceStartupFixture
{
	let suite: String
	let defaults: UserDefaults
	let storage: LocalStorage
	let directory: URL
	let contexts: ProjectContextStore
	init() throws
	{
		suite = "WorkspaceSourceStartup.\(UUID())"
		defaults = UserDefaults(suiteName: suite)!
		storage = LocalStorage(defaults: defaults)
		directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
		contexts = ProjectContextStore(directory: directory.appendingPathComponent("contexts"))
		try FileManager.default.createDirectory(
			at: directory,
			withIntermediateDirectories: true
		)
	}
	func project(_ name: String) throws -> URL
	{
		let project = directory.appendingPathComponent(name).resolvingSymlinksInPath()
		try FileManager.default.createDirectory(
			at: project.appendingPathComponent(".git"),
			withIntermediateDirectories: true
		)
		return project
	}
	func makeStore(managed: TaskWorkspace? = nil) -> WorkspaceStateStore
	{
		let session = UUID()
		let identity = WorkspaceIdentity(
			sessionID: session,
			canonicalCheckoutPath: managed?.checkoutPath
		)
		let owner = managed.map
		{
			WorkspaceLifecycleOwner.managed(
				workspaceID: $0.id,
				sessionID: session
			)
		}
		?? .source(sessionID: session)
		return WorkspaceStoreFactory.make(
			configuration: WorkspaceStoreConfiguration(
				reference: WorkspaceLifecycleOwnerReference(
					owner: owner,
					workspace: identity
				),
				managedWorkspace: managed
			),
			dependencies: WorkspaceStoreDependencies(
				storage: storage,
				projectContextStore: contexts
			)
		)
	}
	func remove()
	{
		defaults.removePersistentDomain(forName: suite)
		try? FileManager.default.removeItem(at: directory)
	}
}
