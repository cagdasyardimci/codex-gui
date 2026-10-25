import Foundation
import Testing

@testable import CodexGUI

@Suite(
	"Project context failure runtime"
)
struct ProjectContextFailureRuntimeTests
{
	@Test("Unsupported and wrong-project context bytes remain unchanged")
	@MainActor
	func protectedContextDocumentsArePreserved() async throws
	{
		for field in ["version", "projectPath"]
		{
			let directory = temporaryDirectory()
			defer
			{
				try? FileManager.default.removeItem(at: directory)
			}
			let project = directory.appendingPathComponent("project")
			let store = ProjectContextStore(directory: directory)
			try store.save(
				ProjectContext(),
				for: project
			)
			let file = store.fileURL(for: project)
			var document = try #require(
				JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
			)
			document[field] = field == "version" ? (999 as Any) : ("/another/project" as Any)
			let original = try JSONSerialization.data(withJSONObject: document)
			try original.write(to: file)
			#expect(throws: ProjectContextStoreError.self)
			{
				try store.load(for: project)
			}
			var edit = ProjectContext()
			edit.savedPrompts = [SavedPrompt(
				title: "Visible edit",
				instructions: "Keep me"
			)]
			#expect(throws: ProjectContextStoreError.self)
			{
				try store.save(
					edit,
					for: project
				)
			}
			#expect(try Data(contentsOf: file) == original)
			let workspace = WorkspaceStateStore(
				model: WorkspaceModel(identity: WorkspaceIdentity(
					sessionID: UUID(),
					canonicalCheckoutPath: project.standardizedFileURL.resolvingSymlinksInPath()
						.path
				)),
				service: AppServer(),
				persistence: WorkspacePersistenceScheduler(writeDraft:
					{
						_ in
					}),
				projectContextStore: store,
				reducers: [ContextNavigationReducer.reducer]
			)
			let save = ContextSaveOperation(
				context: workspace.operationContext(),
				revision: 1,
				value: edit
			)
			workspace.dispatch(.contextNavigation(.contextEdited(save)))
			#expect(workspace.model.contextNavigation.projectContext == edit)
			let handle = try #require(workspace.operation(for: save.context))
			_ = await handle.wait()
			#expect(workspace.model.contextNavigation.projectContext == edit)
			#expect(workspace.model.contextNavigation.contextError != nil)
			#expect(try Data(contentsOf: file) == original)
		}
	}

	private func temporaryDirectory() -> URL
	{
		FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString,
			isDirectory: true
		)
	}
}
