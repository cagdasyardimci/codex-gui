import Foundation

enum SlashCommandID: String, CaseIterable, Sendable
{
	case new, resume, fork, rename, archive, delete, compact, review
	case model, reasoning, fast, permissions, plan, status
	case skills, mention, diff, copy
}

enum SlashCommandArgumentKind: Equatable, Sendable
{
	case none
	case optionalIdentifier
	case optionalText
	case optionalPrompt
	case optionalChoice([String])
	case reviewTarget
}

struct SlashCommandDescriptor: Equatable, Identifiable, Sendable
{
	let id: SlashCommandID
	let description: String
	let aliases: [String]
	let argumentKind: SlashCommandArgumentKind
	let usage: String

	var name: String
	{
		id.rawValue
	}
	var acceptsInlinePrompt: Bool
	{
		argumentKind == .optionalPrompt
	}
	var acceptsArguments: Bool
	{
		argumentKind != .none
	}

	init(
		id: SlashCommandID,
		description: String,
		aliases: [String] = [],
		argumentKind: SlashCommandArgumentKind = .none,
		usage: String? = nil
	)
	{
		self.id = id
		self.description = description
		self.aliases = aliases
		self.argumentKind = argumentKind
		self.usage = usage ?? "/\(id.rawValue)"
	}
}

/// Names, help, completion and argument validation share this command catalog.
enum SlashCommandRegistry
{
	static let commands: [SlashCommandDescriptor] = [
		SlashCommandDescriptor(
			id: .new,
			description: "Start a new conversation"
		),
		SlashCommandDescriptor(
			id: .resume,
			description: "Resume a saved conversation",
			argumentKind: .optionalIdentifier,
			usage: "/resume [thread-id]"
		),
		SlashCommandDescriptor(
			id: .fork,
			description: "Fork the current conversation"
		),
		SlashCommandDescriptor(
			id: .rename,
			description: "Rename the current conversation",
			argumentKind: .optionalText,
			usage: "/rename [name]"
		),
		SlashCommandDescriptor(
			id: .archive,
			description: "Archive the current conversation"
		),
		SlashCommandDescriptor(
			id: .delete,
			description: "Delete the current conversation"
		),
		SlashCommandDescriptor(
			id: .compact,
			description: "Compact the conversation context"
		),
		SlashCommandDescriptor(
			id: .review,
			description: "Review changes, a branch, a commit, or custom instructions",
			argumentKind: .reviewTarget,
			usage: "/review [uncommitted|base <branch>|commit <sha>|custom <instructions>]"
		),
		SlashCommandDescriptor(
			id: .model,
			description: "Choose the model",
			argumentKind: .optionalIdentifier,
			usage: "/model [model-id]"
		),
		SlashCommandDescriptor(
			id: .reasoning,
			description: "Choose the reasoning effort",
			argumentKind: .optionalIdentifier,
			usage: "/reasoning [effort]"
		),
		SlashCommandDescriptor(
			id: .fast,
			description: "Toggle fast mode, or set it on or off",
			argumentKind: .optionalChoice(["on", "off"]),
			usage: "/fast [on|off]"
		),
		SlashCommandDescriptor(
			id: .permissions,
			description: "Choose approval permissions",
			argumentKind: .optionalChoice(["ask", "auto", "full"]),
			usage: "/permissions [ask|auto|full]"
		),
		SlashCommandDescriptor(
			id: .plan,
			description: "Toggle plan mode, or send a prompt in plan mode",
			argumentKind: .optionalPrompt,
			usage: "/plan [prompt]"
		),
		SlashCommandDescriptor(
			id: .status,
			description: "Show conversation and context status"
		),
		SlashCommandDescriptor(
			id: .skills,
			description: "Open the skill picker"
		),
		SlashCommandDescriptor(
			id: .mention,
			description: "Add a file or context mention"
		),
		SlashCommandDescriptor(
			id: .diff,
			description: "Open the conversation diff"
		),
		SlashCommandDescriptor(
			id: .copy,
			description: "Copy the latest assistant response"
		),
	]

	static func descriptor(for name: String) -> SlashCommandDescriptor?
	{
		let normalized = name.lowercased()
		return commands.first
		{
			$0.name == normalized || $0.aliases.contains(normalized)
		}
	}

	static func descriptor(for id: SlashCommandID) -> SlashCommandDescriptor
	{
		// Every command ID is represented exactly once; registry tests enforce this invariant.
		commands.first
		{
			$0.id == id
		}!
	}

	static func matching(prefix: String) -> [SlashCommandDescriptor]
	{
		let normalized = prefix.lowercased()
		return commands.filter
		{
			$0.name.hasPrefix(normalized) || $0.aliases.contains
			{
				$0.hasPrefix(normalized)
			}
		}
	}
}
