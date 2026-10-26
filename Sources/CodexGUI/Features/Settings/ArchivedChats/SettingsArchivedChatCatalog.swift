import Foundation

/// Session source records the originating client; it does not identify a cloud executor.
enum SettingsArchivedChatSource: Equatable
{
	case cli, vscode, exec, appServer, unknown, subAgent
	case custom(String)

	init(json: Any?)
	{
		if let source = json as? String
		{
			switch source
			{
			case "cli": self = .cli
			case "vscode": self = .vscode
			case "exec": self = .exec
			case "appServer": self = .appServer
			default: self = .unknown
			}
		}
		else if let source = json as? [String: Any]
		{
			if let custom = source["custom"] as? String
			{
				self = .custom(custom)
			}
			else if source["subAgent"] != nil
			{
				self = .subAgent
			}
			else
			{
				self = .unknown
			}
		}
		else
		{
			self = .unknown
		}
	}
}

struct SettingsArchivedChat: Identifiable
{
	let id: String
	let title: String
	let preview: String
	let cwd: String?
	let createdAt: Date?
	let updatedAt: Date?
	let source: SettingsArchivedChatSource
	let projectID: String?
	let projectName: String
}

struct SettingsArchivedChatGroup: Identifiable
{
	let id: String?
	let title: String
	let chats: [SettingsArchivedChat]
}

/// Groups server metadata without inspecting the filesystem or invoking Git per conversation.
struct SettingsArchivedChatCatalog
{
	enum Kind: String, CaseIterable
	{
		case local, cloud
	}

	enum Sort: String, CaseIterable
	{
		case updated, created, alphabetical
	}

	static let noProjectID = "__no_project__"
	let chats: [SettingsArchivedChat]

	init(
		threads: [[String: Any]],
		projects: [[String: Any]] = [],
		checkoutProjects: [String: String] = [:],
		projectNames: [String: String] = [:]
	)
	{
		var namesByID: [String: String] = [:]
		for project in projects
		{
			guard let id = Self.nonempty(project["id"] as? String)
			else
			{
				continue
			}
			let root = (project["roots"] as? [[String: Any]])?
				.compactMap
				{
					Self.path($0["path"] as? String)
				}.first
			namesByID[id] = Self.nonempty(project["name"] as? String)
				?? root.map(Self.pathName) ?? "Project \(id)"
		}
		var normalizedCheckouts: [String: String] = [:]
		for (checkout, source) in checkoutProjects
		{
			guard let checkout = Self.path(checkout),
					let source = Self.path(source)
			else
			{
				continue
			}
			normalizedCheckouts[checkout] = source
		}
		var normalizedNames: [String: String] = [:]
		for (path, name) in projectNames
		{
			guard let path = Self.path(path), let name = Self.nonempty(name)
			else
			{
				continue
			}
			normalizedNames[path] = name
		}
		let checkoutRoots = normalizedCheckouts.keys.sorted
		{
			$0.count > $1.count
		}
		let namedRoots = normalizedNames.keys.sorted
		{
			$0.count > $1.count
		}
		var seen = Set<String>()
		chats = threads.compactMap
		{
			json in
			guard let id = Self.nonempty(json["id"] as? String), seen.insert(id).inserted,
					let summary = ThreadSummary(json: json)
			else
			{
				return nil
			}
			let cwd = Self.path(json["cwd"] as? String)
			let projectID: String?
			let projectName: String
			if let serverID = Self.nonempty(json["projectId"] as? String)
			{
				projectID = "project:\(serverID)"
				projectName = namesByID[serverID] ?? "Project \(serverID)"
			}
			else if let cwd
			{
				let canonical = Self.canonicalProject(
					cwd,
					checkouts: normalizedCheckouts,
					checkoutRoots: checkoutRoots,
					namedRoots: namedRoots
				)
				projectID = "path:\(canonical)"
				projectName = normalizedNames[canonical] ?? Self.pathName(canonical)
			}
			else
			{
				projectID = nil
				projectName = "No project"
			}
			return SettingsArchivedChat(
				id: id,
				title: summary.displayTitle,
				preview: json["preview"] as? String ?? "",
				cwd: cwd,
				createdAt: Self.date(json["createdAt"]),
				updatedAt: Self.date(json["updatedAt"]),
				source: SettingsArchivedChatSource(json: json["source"]),
				projectID: projectID,
				projectName: projectName
			)
		}
	}

	func filter(
		query: String = "",
		projectID: String? = nil,
		kind: Kind? = nil,
		sort: Sort = .updated
	) -> [SettingsArchivedChatGroup]
	{
		// thread/list is the local host archive. SessionSource is not a cloud discriminator.
		guard kind != .cloud
		else
		{
			return []
		}
		let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let filtered = chats.filter
		{
			chat in
			let projectMatches = projectID == nil
				|| projectID == (chat.projectID ?? Self.noProjectID)
			let queryMatches = query.isEmpty || chat.title.localizedCaseInsensitiveContains(query)
				|| chat.preview.localizedCaseInsensitiveContains(query)
			return projectMatches && queryMatches
		}
		let grouped = Dictionary(grouping: filtered)
		{
			$0.projectID ?? Self.noProjectID
		}
		return grouped.map
		{
			key, chats in
			SettingsArchivedChatGroup(
				id: key == Self.noProjectID ? nil : key,
				title: chats.first?.projectName ?? "No project",
				chats: chats.sorted
				{
					left, right in
					Self.precedes(
						left,
						right,
						sort: sort
					)
				}
			)
		}.sorted
		{
			left, right in
			if (left.id == nil) != (right.id == nil)
			{
				return left.id == nil
			}
			let comparison = left.title.localizedCaseInsensitiveCompare(right.title)
			return comparison == .orderedSame ? (left.id ?? "") < (right.id ?? "")
				: comparison == .orderedAscending
		}
	}

	private static func precedes(
		_ left: SettingsArchivedChat,
		_ right: SettingsArchivedChat,
		sort: Sort
	) -> Bool
	{
		if sort == .alphabetical
		{
			let order = left.title.localizedCaseInsensitiveCompare(right.title)
			if order != .orderedSame
			{
				return order == .orderedAscending
			}
		}
		else
		{
			let leftDate = sort == .updated ? left.updatedAt ?? left.createdAt : left
				.createdAt ?? left.updatedAt
			let rightDate = sort == .updated ? right.updatedAt ?? right.createdAt : right
				.createdAt ?? right.updatedAt
			if leftDate !=
				rightDate
			{
				return (leftDate ?? .distantPast) > (rightDate ?? .distantPast)
			}
		}
		return left.id < right.id
	}

	private static func canonicalProject(
		_ cwd: String,
		checkouts: [String: String],
		checkoutRoots: [String],
		namedRoots: [String]
	) -> String
	{
		var path = cwd
		var seen = Set<String>()
		while let checkout = checkoutRoots.first(where:
			{
				contains(
					root: $0,
					path: path
				)
			}),
			let source = checkouts[checkout], source != path
		{
			guard seen.insert(path).inserted
			else
			{
				return seen.sorted().first ?? path
			}
			path = source
		}
		return namedRoots.first(where:
			{
				contains(
					root: $0,
					path: path
				)
			}) ?? path
	}

	private static func contains(
		root: String,
		path: String
	) -> Bool
	{
		path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
	}

	private static func path(_ value: String?) -> String?
	{
		guard let value = nonempty(value), value.hasPrefix("/")
		else
		{
			return nil
		}
		return URL(fileURLWithPath: value).standardizedFileURL.path
	}

	private static func pathName(_ path: String) -> String
	{
		let name = URL(fileURLWithPath: path).lastPathComponent
		return name.isEmpty ? path : name
	}

	private static func nonempty(_ value: String?) -> String?
	{
		guard let value
		else
		{
			return nil
		}
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}

	private static func date(_ value: Any?) -> Date?
	{
		guard let seconds = value as? Double, seconds.isFinite
		else
		{
			return nil
		}
		return Date(timeIntervalSince1970: seconds)
	}
}
