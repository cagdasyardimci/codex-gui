import Foundation

/// Inline image payloads are data, never filesystem paths or remote resources.
enum InlineImageData
{
	static func isDataURL(_ value: String) -> Bool
	{
		value.prefix(11).lowercased() == "data:image/"
	}

	static func decode(
		_ value: String,
		maximumBytes: Int
	) -> Data?
	{
		guard !Task.isCancelled, maximumBytes > 0, maximumBytes <= Int.max / 4,
				isDataURL(value), value.utf8.count <= maximumBytes * 4 / 3 + 1_024,
				let comma = value.firstIndex(of: ","),
				value[..<comma].lowercased().hasSuffix(";base64"),
				let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
				!Task.isCancelled, data.count <= maximumBytes
		else
		{
			return nil
		}
		return data
	}
}
