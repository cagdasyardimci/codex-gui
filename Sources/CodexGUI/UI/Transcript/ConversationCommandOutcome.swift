import Foundation

/// One command outcome drives compact headers, group counts and expanded details.
enum ConversationCommandOutcome
{
	case failed(Int?)
	case declined
	case interrupted
	case completed(Bool)
	case running

	init(_ command: ConversationCommand)
	{
		switch command.status
		{
		case "declined": self = .declined
		case "interrupted", "cancelled", "canceled", "stopped": self = .interrupted
		default:
			if let code = command.exitCode, code != 0
			{
				self = .failed(code)
			}
			else if command.status == "failed"
			{
				self = .failed(nil)
			}
			else if command.status == "completed"
			{
				self = .completed(command.exitCode == 0)
			}
			else
			{
				self = .running
			}
		}
	}

	var exceptionalTitle: String?
	{
		switch self
		{
		case .failed(let code): code.map
		{
			"Exit \($0)"
		} ?? "Failed"
		case .declined: "Declined"
		case .interrupted: "Interrupted"
		case .completed, .running: nil
		}
	}

	var groupTitle: String?
	{
		switch self
		{
		case .failed: "failed"
		case .declined: "declined"
		case .interrupted: "interrupted"
		case .completed, .running: nil
		}
	}

	var detailTitle: String
	{
		switch self
		{
		case .failed(let code): code.map
		{
			"Exit code \($0)"
		} ?? "Failed"
		case .declined: "Declined"
		case .interrupted: "Interrupted"
		case .completed(let succeeded): succeeded ? "✓ Success" : "Completed"
		case .running: "Running…"
		}
	}
}
