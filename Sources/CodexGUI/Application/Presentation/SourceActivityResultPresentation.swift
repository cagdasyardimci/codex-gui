import Foundation

/// Prepares bounded, stable text for recorded source activity.
struct SourceActivityResultPresentation
{
	static func displayOutput(_ output: String) -> (text: String, language: String)
	{
		(truncated(
			output,
			limit: 16_384
		), "text")
	}

	static func detailDescription(_ json: [String: Any]) -> String
	{
		let fields = ["id",
						"type",
						"server",
						"namespace",
						"tool",
						"status",
						"arguments",
						"result",
						"contentItems",
						"action",
						"query",
						"results",
						"error",
						"appContext",
						"mcpAppUi",
						"mcpAppResourceUri",
						"pluginId",
						"durationMs",
						"success",
						"command",
						"cwd",
						"aggregatedOutput",
						"exitCode"]
		var details: [String: Any] = [:]
		for key in fields where json[key] != nil
		{
			details[key] = Self.bounded(
				json[key]!,
				depth: 0
			)
		}
		let data = try? JSONSerialization.data(
			withJSONObject: details,
			options: [.sortedKeys, .prettyPrinted]
		)
		return Self.truncated(
			data.flatMap
			{
				String(
					data: $0,
					encoding: .utf8
				)
			} ?? "",
			limit: 16_384
		)
	}

	/// Caps JSON input before parsing and reduces whole values without slicing JSON.
	private static func decodedJSON(_ text: String) -> Any?
	{
		guard text.utf8.count <= 2 * 1_024 * 1_024, let data = text.data(using: .utf8)
		else
		{
			return nil
		}
		return try? JSONSerialization.jsonObject(
			with: data,
			options: [.fragmentsAllowed]
		)
	}

	static func errorPayload(
		_ value: Any,
		depth: Int = 0
	) -> (text: String, language: String)
	{
		guard depth < 6
		else
		{
			return ("[Nested error data omitted]", "text")
		}
		if let text = value as? String
		{
			if let object = decodedJSON(text) as? [String: Any]
			{
				return errorPayload(
					object,
					depth: depth + 1
				)
			}
			return (truncated(
				text,
				limit: 16_384
			), "text")
		}
		if let object = value as? [String: Any]
		{
			for key in ["message", "error", "text", "detail"]
			{
				if let message = object[key], hasDisplayValue(message)
				{
					return errorPayload(
						message,
						depth: depth + 1
					)
				}
			}
		}
		return (displayValue(value).text, "text")
	}

	/// Empty protocol candidates must not hide a later recorded result or error message.
	static func hasDisplayValue(
		_ value: Any,
		depth: Int = 0
	) -> Bool
	{
		guard depth < 8
		else
		{
			return true
		}
		if value is NSNull
		{
			return false
		}
		if let text = value as? String
		{
			return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		}
		if let values = value as? [Any]
		{
			return values.count > 32 || values.prefix(32).contains
			{
				hasDisplayValue(
					$0,
					depth: depth + 1
				)
			}
		}
		if let fields = value as? [String: Any]
		{
			return fields.count > 64 || fields.values.prefix(64).contains
			{
				hasDisplayValue(
					$0,
					depth: depth + 1
				)
			}
		}
		return true
	}

	static func displayContent(
		_ content: [[String: Any]],
		isError: Bool = false
	) -> (text: String, language: String)
	{
		if isError
		{
			return displayErrorContent(content)
		}
		let values = content.prefix(24).compactMap(contentValue)
		guard !values.isEmpty
		else
		{
			return ("", "")
		}
		if values.count == 1, content.count <= 24
		{
			return displayValue(values[0])
		}
		var decoded: [Any] = []
		var allJSON = true
		for value in values
		{
			if let text = value as? String
			{
				if let parsed = decodedJSON(text)
				{
					decoded.append(parsed)
				}
				else
				{
					allJSON = false
					decoded.append(truncated(
						text,
						limit: 4_096
					))
				}
			}
			else
			{
				decoded.append(value)
			}
		}
		if content.count > 24
		{
			decoded.append("[Remaining result content omitted]")
		}
		if allJSON
		{
			return displayValue(decoded)
		}
		let text = decoded.map
		{
			value in
			(value as? String) ?? displayValue(value).text
		}.joined(separator: "\n\n")
		return (truncated(
			text,
			limit: 16_384
		), "text")
	}

	private static func displayErrorContent(
		_ content: [[String: Any]]
	) -> (text: String, language: String)
	{
		let limit = 16_384
		var remaining = limit
		var omitted = content.count > 24
		var parts: [String] = []
		for item in content.prefix(24)
		{
			let separatorLength = parts.isEmpty ? 0 : 2
			guard remaining > separatorLength
			else
			{
				omitted = true
				break
			}
			guard let value = contentValue(item)
			else
			{
				continue
			}
			let text = errorPayload(value).text
			guard !text.isEmpty
			else
			{
				continue
			}
			let available = remaining - separatorLength
			let part = String(text.prefix(available))
			parts.append(part)
			remaining -= separatorLength + part.count
			if text.count > available
			{
				omitted = true
				break
			}
		}
		let text = parts.joined(separator: "\n\n")
		if omitted
		{
			let marker = "\n\n[Remaining result content omitted]"
			return (String(text.prefix(limit - marker.count)) + marker, "text")
		}
		return (text, "text")
	}

	private static func contentValue(_ content: [String: Any]) -> Any?
	{
		let type = content["type"] as? String
		if type == nil || type == "text", let text = content["text"] as? String
		{
			return hasDisplayValue(text) ? text : nil
		}
		if type == "resource", let resource = content["resource"] as? [String: Any]
		{
			var fields = resource
			fields["type"] = "resource"
			if let blob = fields["blob"] as? String
			{
				fields["blob"] = "[Recorded binary resource: \(blob.utf8.count) encoded bytes]"
			}
			return fields
		}
		if let type, type == "image" || type == "audio"
		{
			var fields = content
			if let data = fields["data"] as? String
			{
				fields["data"] = "[Recorded \(type) data: \(data.utf8.count) encoded bytes]"
			}
			return fields
		}
		// Resource links retain URI, title and MIME metadata. Unknown kinds remain inspectable
		// through the same bounded JSON presentation instead of appearing to have no result.
		return hasDisplayValue(content) ? content : nil
	}

	static func displayValue(_ value: Any) -> (text: String, language: String)
	{
		let decoded: Any
		if let text = value as? String
		{
			guard let parsed = decodedJSON(text)
			else
			{
				return (
					truncated(
						text,
						limit: 16_384
					),
					"text"
				)
			}
			decoded = parsed
		}
		else
		{
			decoded = value
		}
		// Escaping and indentation also consume card space. Reduce whole subtrees until the
		// serialized result fits, rather than cutting an otherwise valid JSON document.
		for (characterLimit, nodeLimit) in [(8_192, 256), (4_096, 128), (2_048, 64), (1_024, 32)]
		{
			var characters = characterLimit
			var nodes = nodeLimit
			let boundedValue = displayBounded(
				decoded,
				depth: 0,
				characters: &characters,
				nodes: &nodes
			)
			guard let text = prettyJSON(boundedValue)
			else
			{
				return (
					"[Result could not be displayed]",
					"text"
				)
			}
			if text.count <= 16_384
			{
				return (text, "json")
			}
		}
		return ("{\n  \"remainingDisplayData\": \"Result exceeds display limits\"\n}", "json")
	}

	/// Preserve schema and shallow metadata before allocating budget to large item arrays.
	private static func displayKeys(_ object: [String: Any]) -> [String]
	{
		func priority(_ key: String) -> Int
		{
			if key == "schemaVersion"
			{
				return -2
			}
			if key == "sidebarPreferences"
			{
				return -1
			}
			if object[key] is [Any]
			{
				return 2
			}
			if object[key] is [String: Any]
			{
				return 1
			}
			return 0
		}
		return object.keys.sorted
		{
			let left = priority($0)
			let right = priority($1)
			return left == right ? $0 < $1 : left < right
		}
	}

	private static func displayBounded(
		_ value: Any,
		depth: Int,
		characters: inout Int,
		nodes: inout Int
	) -> Any
	{
		guard depth < 8, characters > 0, nodes > 0
		else
		{
			return "[Remaining result data omitted]"
		}
		nodes -= 1
		if let text = value as? String
		{
			let limit = min(
				characters,
				4_096
			)
			characters -= min(
				text.count,
				limit
			)
			return truncated(
				text,
				limit: limit
			)
		}
		if let array = value as? [Any]
		{
			var result: [Any] = []
			for (index, item) in array.prefix(32).enumerated()
			{
				guard characters > 0, nodes > 0
				else
				{
					break
				}
				let remainingItems = min(
					8,
					array.count - index
				)
				var itemCharacters = min(
					characters,
					max(
						512,
						characters / remainingItems
					)
				)
				var itemNodes = min(
					nodes,
					max(
						16,
						nodes / remainingItems
					)
				)
				let allocatedCharacters = itemCharacters
				let allocatedNodes = itemNodes
				result.append(displayBounded(
					item,
					depth: depth + 1,
					characters: &itemCharacters,
					nodes: &itemNodes
				))
				characters -= allocatedCharacters - itemCharacters
				nodes -= allocatedNodes - itemNodes
			}
			if result.count < array.count
			{
				result.append("[Remaining result items omitted]")
			}
			return result
		}
		if let object = value as? [String: Any]
		{
			var result: [String: Any] = [:]
			let keys = Array(displayKeys(object).prefix(64))
			for (index, key) in keys.enumerated()
			{
				guard characters > 0, nodes > 0
				else
				{
					break
				}
				let keyLimit = min(
					characters,
					512
				)
				let boundedKey = truncated(
					key,
					limit: keyLimit
				)
				characters -= min(
					key.count,
					keyLimit
				)
				let remainingKeys = min(
					8,
					keys.count - index
				)
				var fieldCharacters = min(
					characters,
					max(
						512,
						characters / remainingKeys
					)
				)
				var fieldNodes = min(
					nodes,
					max(
						16,
						nodes / remainingKeys
					)
				)
				let allocatedCharacters = fieldCharacters
				let allocatedNodes = fieldNodes
				result[boundedKey] = displayBounded(
					object[key]!,
					depth: depth + 1,
					characters: &fieldCharacters,
					nodes: &fieldNodes
				)
				characters -= allocatedCharacters - fieldCharacters
				nodes -= allocatedNodes - fieldNodes
			}
			if result.count < object
				.count
			{
				result["remainingDisplayData"] = "Remaining result fields omitted"
			}
			return result
		}
		return value
	}

	/// Serializes a bounded value in deterministic metadata-first order while keeping JSON valid.
	private static func prettyJSON(
		_ value: Any,
		depth: Int = 0
	) -> String?
	{
		let indent = String(
			repeating: "  ",
			count: depth
		)
		let childIndent = indent + "  "
		if let object = value as? [String: Any]
		{
			guard !object.isEmpty
			else
			{
				return "{}"
			}
			var lines: [String] = []
			for key in displayKeys(object)
			{
				guard let encodedKey = prettyJSON(key), let encodedValue = prettyJSON(
					object[key]!,
					depth: depth + 1
				)
				else
				{
					return nil
				}
				lines.append(childIndent + encodedKey + ": " + encodedValue)
			}
			return "{\n" + lines.joined(separator: ",\n") + "\n" + indent + "}"
		}
		if let array = value as? [Any]
		{
			guard !array.isEmpty
			else
			{
				return "[]"
			}
			var lines: [String] = []
			for item in array
			{
				guard let encoded = prettyJSON(
					item,
					depth: depth + 1
				)
				else
				{
					return nil
				}
				lines.append(childIndent + encoded)
			}
			return "[\n" + lines.joined(separator: ",\n") + "\n" + indent + "]"
		}
		guard let data = try? JSONSerialization.data(
			withJSONObject: value,
			options: [.fragmentsAllowed, .withoutEscapingSlashes]
		)
		else
		{
			return nil
		}
		return String(
			data: data,
			encoding: .utf8
		)
	}

	static func truncated(
		_ string: String,
		limit: Int
	) -> String
	{
		string.count > limit ? String(string.prefix(limit)) + "\n[Remaining data omitted]" : string
	}

	private static func bounded(
		_ value: Any,
		depth: Int
	) -> Any
	{
		guard depth < 6
		else
		{
			return "[Nested data omitted]"
		}
		if let string = value as? String
		{
			return truncated(
				string,
				limit: 4_096
			)
		}
		if let array = value as? [Any]
		{
			var result = array.prefix(24).map
			{
				bounded(
					$0,
					depth: depth + 1
				)
			}
			if array.count > 24
			{
				result.append("[Remaining items omitted]")
			}
			return result
		}
		if let object = value as? [String: Any]
		{
			var result: [String: Any] = [:]
			for key in object.keys.sorted().prefix(32)
			{
				result[key] = bounded(
					object[key]!,
					depth: depth + 1
				)
			}
			if object.count > 32
			{
				result["_omitted"] = "Remaining fields omitted"
			}
			return result
		}
		return value
	}

}
