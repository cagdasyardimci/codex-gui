import Foundation

/// Navigation metadata carries no message, tool, or command content.
struct ConversationTurnReference: Equatable, Sendable
{
	let id: String
	let status: String
	var startedAt: Date? = nil
	var completedAt: Date? = nil
	var durationMs: Double? = nil
	var error: String? = nil

	init(
		id: String,
		status: String,
		startedAt: Date? = nil,
		completedAt: Date? = nil,
		durationMs: Double? = nil,
		error: String? = nil
	)
	{
		self.id = id
		self.status = status
		self.startedAt = startedAt
		self.completedAt = completedAt
		self.durationMs = durationMs
		self.error = error
	}

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String, !id.isEmpty
		else
		{
			return nil
		}
		self.init(
			id: id,
			status: json["status"] as? String ?? "completed",
			startedAt: (json["startedAt"] as? NSNumber)
				.map
				{
					Date(timeIntervalSince1970: $0.doubleValue)
				},
			completedAt: (json["completedAt"] as? NSNumber)
				.map
				{
					Date(timeIntervalSince1970: $0.doubleValue)
				},
			durationMs: (json["durationMs"] as? NSNumber)?.doubleValue,
			error: (json["error"] as? [String: Any])?["message"] as? String
		)
	}
}

struct TurnReferencePage: Sendable
{
	let references: [ConversationTurnReference]
	let nextCursor: String?
}
