import CryptoKit
import Foundation

struct ThreadQueuedSubmission: Equatable, Sendable
{
	let id: String
	let clientUserMessageID: String
	let inputJSON: Data

	init(json: [String: Any]) throws
	{
		guard let id = json["id"] as? String, !id.isEmpty,
				let clientID = json["clientUserMessageId"] as? String, !clientID.isEmpty,
				let input = json["input"] as? [[String: Any]]
		else
		{
			throw AppServerError.protocolError("Invalid queued submission.")
		}
		self.id = id
		clientUserMessageID = clientID
		inputJSON = try JSONSerialization.data(
			withJSONObject: input,
			options: [.sortedKeys]
		)
	}

	var localID: UUID
	{
		if let id = UUID(uuidString: clientUserMessageID)
		{
			return id
		}
		let bytes = Array(SHA256.hash(data: Data(clientUserMessageID.utf8)).prefix(16))
		return UUID(uuid: (
			bytes[0],
			bytes[1],
			bytes[2],
			bytes[3],
			bytes[4],
			bytes[5],
			bytes[6],
			bytes[7],
			bytes[8],
			bytes[9],
			bytes[10],
			bytes[11],
			bytes[12],
			bytes[13],
			bytes[14],
			bytes[15]
		))
	}

	var input: [[String: Any]]
	{
		(try? JSONSerialization.jsonObject(with: inputJSON)) as? [[String: Any]] ?? []
	}

	var contextItems: [ComposerContextItem]
	{
		input.compactMap
		{
			value in
			guard let path = value["path"] as? String
			else
			{
				return nil
			}
			if value["type"] as? String == "localImage"
			{
				return ComposerContextItem(
					kind: .image,
					title: URL(fileURLWithPath: path).lastPathComponent,
					path: path
				)
			}
			if value["type"] as? String == "mention"
			{
				return ComposerContextItem(
					kind: .fileReference,
					title: value["name"] as? String ?? URL(fileURLWithPath: path).lastPathComponent,
					path: path
				)
			}
			return nil
		}
	}

	var preview: String
	{
		let text = input.compactMap
		{
			$0["text"] as? String
		}.joined(separator: "\n")
		if !text.isEmpty
		{
			return text
		}
		return input.compactMap
		{
			value in
			if let path = value["path"] as? String
			{
				return URL(fileURLWithPath: path).lastPathComponent
			}
			return value["name"] as? String ?? value["type"] as? String
		}.joined(separator: ", ")
	}
}

struct ThreadQueuePage
{
	let data: [ThreadQueuedSubmission]
	let nextCursor: String?
}

struct ThreadQueueUnsupported: Error
{
}
