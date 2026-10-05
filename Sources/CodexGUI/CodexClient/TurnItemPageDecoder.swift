import Foundation

struct DecodedTurnItemPage: Sendable
{
	let items: [CodexItem]
	let nextCursor: String?
}

enum TurnItemPageDecoder
{
	static func decode(
		_ payload: ProtocolJSONPayload,
		turnID: String
	) throws -> DecodedTurnItemPage
	{
		guard let data = payload.value["data"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid turn item page.")
		}
		var items: [CodexItem] = []
		for entry in data
		{
			try Task.checkCancellation()
			guard entry["turnId"] as? String == turnID,
					let raw = entry["item"] as? [String: Any], let item = CodexItem(json: raw)
			else
			{
				throw AppServerError
					.protocolError("Codex returned an item outside the requested turn.")
			}
			items.append(item)
		}
		try Task.checkCancellation()
		return DecodedTurnItemPage(
			items: items,
			nextCursor: payload.value["nextCursor"] as? String
		)
	}
}
