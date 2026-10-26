import AppKit

struct SettingsArchivedProjectContext: Sendable
{
	var checkoutProjects: [String: String] = [:]
	var projectNames: [String: String] = [:]
}

@MainActor
final class SettingsArchivedChatsPage: SettingsManagementPage
{
	private var threads: [[String: Any]] = []
	private var projects: [[String: Any]] = []
	private var projectContext = SettingsArchivedProjectContext()
	private var contextWarning = ""
	private let readProjectContext: @MainActor () async throws -> SettingsArchivedProjectContext
	private lazy var archive = SettingsArchivedChatsView()

	init(
		backend: SettingsBackend,
		readProjectContext: @escaping @MainActor () async throws -> SettingsArchivedProjectContext =
		{
			let storage = LocalStorage()
			var names = storage.projectDisplayNames
			for project in storage.recentProjects where names[project.path] == nil
			{
				names[project.path] = project.lastPathComponent
			}
			let records = try await Task.detached(priority: .utility)
			{
				try TaskWorkspaceStore().loadAll()
			}.value
			var checkouts: [String: String] = [:]
			for record in records
			{
				checkouts[record.checkoutPath] = record.sourceProjectPath
			}
			return SettingsArchivedProjectContext(
				checkoutProjects: checkouts,
				projectNames: names
			)
		}
	)
	{
		self.readProjectContext = readProjectContext
		super.init(
			title: "Archived chats",
			backend: backend
		)
		archive.onRefresh =
		{
			[weak self] in self?.load()
		}
		archive.onUnarchive =
		{
			[weak self] chat in self?.unarchive(chat)
		}
		archive.onDelete =
		{
			[weak self] chat in self?.confirmDelete(chat)
		}
	}

	required init?(coder: NSCoder)
	{
		nil
	}

	override func render()
	{
		if archive.superview == nil
		{
			AppKitLayout.pin(
				archive,
				to: self,
				inset: 0
			)
		}
		archive.update(
			catalog: catalog,
			message: [message, contextWarning].filter
			{
				!$0.isEmpty
			}
			.joined(separator: "\n"),
			busy: isOperating
		)
	}

	private var catalog: SettingsArchivedChatCatalog
	{
		SettingsArchivedChatCatalog(
			threads: threads,
			projects: projects,
			checkoutProjects: projectContext.checkoutProjects,
			projectNames: projectContext.projectNames
		)
	}

	override func load()
	{
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			let loaded = try await readList(
				"thread/list",
				parameters: [
					"archived": true,
					"limit": 100,
					"sortKey": "updated_at",
					"sortDirection": "desc"
				]
			)
			var warnings: [String] = []
			do
			{
				projects = try await readList(
					"project/list",
					parameters: ["limit": 100]
				)
			}
			catch
			{
				warnings.append("Project names could not be loaded: " + error.localizedDescription)
			}
			do
			{
				projectContext = try await readProjectContext()
			}
			catch
			{
				warnings
					.append("Worktree groups could not be loaded: " + error.localizedDescription)
			}
			try Task.checkCancellation()
			threads = loaded
			contextWarning = warnings.joined(separator: "\n")
		}
	}

	private func readList(
		_ method: String,
		parameters: [String: Any]
	) async throws -> [[String: Any]]
	{
		var rows: [[String: Any]] = []
		var cursor: String?
		var tracker =
			PaginationCursorTracker(repeatedCursorMessage: "Codex repeated the archive cursor.")
		repeat
		{
			var params = parameters
			if let cursor
			{
				params["cursor"] = cursor
			}
			let result = try await backend.perform(
				method,
				params: params
			)
			guard let data = result["data"] as? [[String: Any]]
			else
			{
				throw AppServerError.protocolError("Codex returned an invalid archive list.")
			}
			rows += data
			cursor = try tracker.advance(to: result["nextCursor"] as? String)
		}
		while cursor != nil
		return rows
	}

	private func unarchive(_ chat: SettingsArchivedChat)
	{
		guard !isOperating, catalog.chats.contains(where:
			{
				$0.id == chat.id
			})
		else
		{
			return
		}
		run
		{
			[weak self] in
			guard let self
			else
			{
				return
			}
			_ = try await backend.perform(
				"thread/unarchive",
				params: ["threadId": chat.id]
			)
			threads.removeAll
			{
				$0["id"] as? String == chat.id
			}
		}
	}

	private func confirmDelete(_ chat: SettingsArchivedChat)
	{
		guard !isOperating, let window, window.attachedSheet == nil
		else
		{
			return
		}
		let confirmation = SettingsArchivedChatDeleteView()
		let panel = SettingsArchivedChatDeletePanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.title = "Delete archived chat?"
		panel.contentViewController = confirmation
		confirmation.view.layoutSubtreeIfNeeded()
		panel.setContentSize(confirmation.view.fittingSize)
		panel.initialFirstResponder = confirmation.cancelButton
		panel.defaultButtonCell = confirmation.cancelButton.cell as? NSButtonCell
		confirmation.onDecision =
		{
			[weak panel] confirmed in
			panel?.finishDecision(confirmed)
		}
		panel.beginSheet(in: window)
		{
			[weak self, panel] response in
			panel.orderOut(nil)
			guard response == .OK, let self, self.window === window
			else
			{
				return
			}
			guard !isOperating,
					catalog.chats.contains(where:
					{
						$0.id == chat.id
					})
			else
			{
				return
			}
			run
			{
				[weak self] in
				guard let self
				else
				{
					return
				}
				let archived = try await readList(
					"thread/list",
					parameters: [
						"archived": true,
						"limit": 100
					]
				)
				guard archived.contains(where:
					{
						$0["id"] as? String == chat.id
					})
				else
				{
					throw AppServerError
						.requestRejected("This chat is no longer archived. Refresh the list.")
				}
				_ = try await backend.perform(
					"thread/delete",
					params: ["threadId": chat.id]
				)
				threads.removeAll
				{
					$0["id"] as? String == chat.id
				}
			}
		}
	}
}
