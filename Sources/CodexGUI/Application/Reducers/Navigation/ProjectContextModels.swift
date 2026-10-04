import Foundation

enum ProjectContextItemKind: String, Codable, CaseIterable, Sendable
{
	case specification
	case referenceFile
	case note
	case decision
}

struct ProjectContextItem: Codable, Equatable, Identifiable, Sendable
{
	var id: String
	var kind: ProjectContextItemKind
	var title: String
	var body: String
	/// A project-relative or absolute path supplied by the user. It is retained even if the file
	/// moves.
	var referencePath: String?
	/// Only items the user selected are eligible for inclusion in a request.
	var isIncluded: Bool

	init(
		id: String = UUID().uuidString,
		kind: ProjectContextItemKind,
		title: String,
		body: String = "",
		referencePath: String? = nil,
		isIncluded: Bool = false
	)
	{
		self.id = id
		self.kind = kind
		self.title = title
		self.body = body
		self.referencePath = referencePath
		self.isIncluded = isIncluded
	}
}

struct SavedPrompt: Codable, Equatable, Identifiable, Sendable
{
	var id: String
	var title: String
	var instructions: String

	init(
		id: String = UUID().uuidString,
		title: String,
		instructions: String
	)
	{
		self.id = id
		self.title = title
		self.instructions = instructions
	}
}

/// A remembered selection. The backend's current skill list remains authoritative for availability.
struct ProjectSkillSelection: Codable, Equatable, Sendable
{
	var name: String
	var description: String
	var path: String? = nil

	var invocationText: String
	{
		"$\(name)"
	}
}

struct ProjectModelPreference: Codable, Equatable, Sendable
{
	/// Nil values explicitly select the backend default. A nil preference falls back to global
	/// choice.
	var modelID: String?
	var effort: String?
}

enum ConversationBookmarkKind: String, Codable, CaseIterable, Sendable
{
	case userRequest
	case answer
	case decision
	case changedFile
	case failure
}

/// Backend identities survive a changed conversation title and allow a jump after history reload.
struct ConversationBookmark: Codable, Equatable, Identifiable, Sendable
{
	var id: String
	var threadID: String
	var turnID: String
	var itemID: String?
	var kind: ConversationBookmarkKind
	var label: String
	var filePath: String?

	init(
		id: String = UUID().uuidString,
		threadID: String,
		turnID: String,
		itemID: String? = nil,
		kind: ConversationBookmarkKind,
		label: String,
		filePath: String? = nil
	)
	{
		self.id = id
		self.threadID = threadID
		self.turnID = turnID
		self.itemID = itemID
		self.kind = kind
		self.label = label
		self.filePath = filePath
	}
}

struct ProjectContext: Codable, Equatable, Sendable
{
	var items: [ProjectContextItem] = []
	var savedPrompts: [SavedPrompt] = []
	var selectedPromptID: String? = nil
	var selectedSkill: ProjectSkillSelection? = nil
	var modelPreference: ProjectModelPreference? = nil
	var bookmarks: [ConversationBookmark] = []

	var selectedPrompt: SavedPrompt?
	{
		savedPrompts.first
		{
			$0.id == selectedPromptID
		}
	}

	/// Builds only the context the user has marked for this request. Callers decide whether to send
	/// it.
	var includedContextText: String
	{
		items.filter(\.isIncluded).map
		{
			item in
			var text = "[\(item.kind.rawValue)] \(item.title)"
			if let path = item.referencePath, !path.isEmpty
			{
				text += "\nFile: \(path)"
			}
			if !item.body.isEmpty
			{
				text += "\n\(item.body)"
			}
			return text
		}.joined(separator: "\n\n")
	}
}
