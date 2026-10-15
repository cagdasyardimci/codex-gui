import Foundation
import Testing
@testable import CodexGUI

@MainActor
@Suite
struct WorkspaceSourceStartupTests
{
	@Test("Explicit project selection overrides the remembered chat in one accepted transition")
	func projectOpeningUsesCapturedThread() throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		let project = try fixture.project("pinned-project")
		fixture.storage.saveSelectedThreadID(
			"remembered-thread",
			for: project
		)
		fixture.storage.saveDraft(
			"Pinned draft",
			for: project,
			threadID: "pinned-thread"
		)
		let store = fixture.makeStore()
		defer
		{
			store.shutdown()
		}
		var projectSelections: [String?] = []
		store.observePublications
		{
			publication in
			guard publication.model.identity.canonicalCheckoutPath == project.path
			else
			{
				return
			}
			projectSelections.append(WorkspaceSelectors(
				model: publication.model,
				now: .distantPast
			).makeSnapshot().selectedThreadID)
		}
		store.inputs.openProject(
			project,
			selectedThreadID: "pinned-thread"
		)
		#expect(store.model.identity.canonicalCheckoutPath == project.path)
		#expect(store.currentSnapshot.selectedThreadID == "pinned-thread")
		#expect(store.currentSnapshot.draft == "Pinned draft")
		#expect(!projectSelections.isEmpty)
		#expect(projectSelections.allSatisfy
		{
			$0 == "pinned-thread"
		})
	}

	@Test("Ordinary project opening retains the remembered chat")
	func projectOpeningUsesRememberedThread() throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		let project = try fixture.project("remembered-project")
		fixture.storage.saveSelectedThreadID(
			"remembered-thread",
			for: project
		)
		let store = fixture.makeStore()
		defer
		{
			store.shutdown()
		}
		store.inputs.openProject(project)
		#expect(store.model.identity.canonicalCheckoutPath == project.path)
		#expect(store.currentSnapshot.selectedThreadID == "remembered-thread")
	}

	@Test("Source startup restores its checkout and draft while context loads before submission")
	func latestProjectIsHydratedBeforeSubmission() async throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		let old = try fixture.project("old")
		let latest = try fixture.project("latest")
		fixture.storage.rememberProject(old)
		fixture.storage.rememberProject(latest)
		fixture.storage.saveSelectedThreadID(
			"old-thread",
			for: old
		)
		fixture.storage.saveSelectedThreadID(
			"latest-thread",
			for: latest
		)
		fixture.storage.saveDraft(
			"Old draft",
			for: old,
			threadID: "old-thread"
		)
		fixture.storage.saveDraft(
			"Latest draft",
			for: latest,
			threadID: "latest-thread"
		)
		fixture.storage.saveModelPreference(
			modelID: "global-model",
			effort: "low"
		)
		var projectContext = ProjectContext()
		projectContext.modelPreference = ProjectModelPreference(
			modelID: "project-model",
			effort: "high"
		)
		try fixture.contexts.save(
			projectContext,
			for: latest
		)
		let store = fixture.makeStore()
		defer
		{
			store.shutdown()
		}
		let initialSession = store.model.identity.sessionID
		let context = store.operationContext()
		store.dispatch(.workspaceLifecycle(.sourceStartupRequested(context)))
		#expect(store.model.identity.sessionID == initialSession)
		#expect(store.model.identity.canonicalCheckoutPath == latest.path)
		#expect(store.model.lifecycle.pendingSourceStartup == nil)
		#expect(store.operation(for: context)?.completion == .finished)
		var observedSnapshot: ConversationSnapshot?
		store.observePublications
		{
			publication in
			observedSnapshot = WorkspaceSelectors(
				model: publication.model,
				now: .distantPast
			).makeSnapshot()
		}
		#expect(observedSnapshot?.projectPath == latest.path)
		#expect(observedSnapshot?.selectedThreadID == "latest-thread")
		#expect(observedSnapshot?.draft == "Latest draft")
		#expect(observedSnapshot?.canSend == false)
		#expect(WorkspaceEligibility(model: store.model).preferenceWarning
			== "Project context is loading.")
		let load = try #require(store.model.contextNavigation.pendingContextLoad)
		let loadHandle = try #require(store.operation(for: load.context))
		#expect(await loadHandle.wait() == .finished)
		#expect(observedSnapshot?.selectedModelID == "project-model")
		#expect(observedSnapshot?.selectedEffort == "high")
		#expect(observedSnapshot?.projectContext == projectContext)
		#expect(observedSnapshot?.canSend == false)
	}

	@Test("A source without a stored project restores global preferences without a checkout")
	func noProjectRestoresGlobalPreferences() throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		fixture.storage.saveModelPreference(
			modelID: "global-model",
			effort: "high"
		)
		fixture.storage.saveRunPreferences(RunPreferences(
			approvalMode: .fullAccess,
			fastMode: true
		))
		let store = fixture.makeStore()
		defer
		{
			store.shutdown()
		}
		let context = store.operationContext()
		store.dispatch(.workspaceLifecycle(.sourceStartupRequested(context)))
		#expect(store.operation(for: context)?.completion == .finished)
		#expect(store.model.identity.canonicalCheckoutPath == nil)
		#expect(store.currentSnapshot.projectPath == nil)
		#expect(store.currentSnapshot.selectedModelID == "global-model")
		#expect(store.currentSnapshot.selectedEffort == "high")
		#expect(store.currentSnapshot.approvalMode == .fullAccess)
		#expect(store.currentSnapshot.fastMode)
		#expect(!store.currentSnapshot.canSend)
	}

	@Test("Managed hydration keeps its durable checkout and thread despite source recents")
	func managedOwnerNeverUsesSourceSelection() throws
	{
		let fixture = try SourceStartupFixture()
		defer
		{
			fixture.remove()
		}
		let source = try fixture.project("source")
		let checkout = try fixture.project("managed")
		fixture.storage.rememberProject(source)
		fixture.storage.saveSelectedThreadID(
			"source-thread",
			for: source
		)
		fixture.storage.saveSelectedThreadID(
			"foreign-selection",
			for: checkout
		)
		fixture.storage.saveDraft(
			"Source draft",
			for: source,
			threadID: "source-thread"
		)
		fixture.storage.saveDraft(
			"Managed draft",
			for: checkout,
			threadID: "managed-thread"
		)
		let managed = TaskWorkspace(
			id: UUID(),
			taskID: "task",
			threadID: "managed-thread",
			sourceProjectPath: source.path,
			repositoryGitDirectory: source.appendingPathComponent(".git").path,
			branch: "codex/task",
			checkoutPath: checkout.path,
			baseCommit: "commit",
			sourceWasDirty: false,
			createdAt: .distantPast,
			phase: .active
		)
		let store = fixture.makeStore(managed: managed)
		defer
		{
			store.shutdown()
		}
		let context = store.operationContext()
		store.dispatch(.workspaceLifecycle(.sourceStartupRequested(context)))
		#expect(store.operation(for: context) == nil)
		#expect(store.model.identity.canonicalCheckoutPath == checkout.path)
		#expect(store.currentSnapshot.selectedThreadID == "managed-thread")
		#expect(store.currentSnapshot.draft == "Managed draft")
		#expect(store.model.lifecycle.managedWorkspace == managed)
		#expect(store.model.lifecycle.pendingSourceStartup == nil)
	}

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
