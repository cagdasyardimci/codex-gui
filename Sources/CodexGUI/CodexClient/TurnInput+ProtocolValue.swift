import Foundation

extension TurnInput
{
	var protocolValue: [String: Any]
	{
		switch self
		{
		case .text(let text):
			["type": "text", "text": text, "text_elements": []]
		case .mention(
			let name,
			let path
		):
			["type": "mention", "name": name, "path": path]
		case .localImage(let path):
			["type": "localImage", "path": path]
		}
	}
}
