import Foundation

/// Decodes only the structured title returned by the helper turn.
enum AutomaticTitleResponse
{
	static func title(_ text: String) -> String?
	{
		guard let data = text.data(using: .utf8),
				let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let title = object["title"] as? String
		else
		{
			return nil
		}
		let normalized = ThreadTitleText.normalized(title)
		return normalized.isEmpty ? nil : normalized
	}
}
