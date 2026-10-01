import Foundation

struct CodexCommandAction: Equatable
{
	enum Kind: String, Equatable
	{
		case read
		case search
		case listFiles
		case unknown
	}

	let kind: Kind
	let command: String
	let name: String?
	let path: String?
	let query: String?

	init(
		kind: Kind,
		command: String,
		name: String? = nil,
		path: String? = nil,
		query: String? = nil
	)
	{
		self.kind = kind
		self.command = command
		self.name = name
		self.path = path
		self.query = query
	}

	init?(json: [String: Any])
	{
		guard let command = json["command"] as? String
		else
		{
			return nil
		}
		self.kind = Kind(rawValue: json["type"] as? String ?? "") ?? .unknown
		self.command = command
		self.name = json["name"] as? String
		self.path = json["path"] as? String
		self.query = json["query"] as? String
	}
}
