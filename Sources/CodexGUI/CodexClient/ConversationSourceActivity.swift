import Foundation

/// Structured, bounded history data. These fields never execute instructions from tool output.
struct ConversationSourceActivity: Equatable, Sendable
{
	enum Kind: Equatable, Sendable
	{
		case tool
		case web
		case terminal
	}

	struct Page: Equatable, Sendable
	{
		let id: String
		let title: String
		let url: String
	}

	let id: String
	let kind: Kind
	let provider: String
	let operation: String
	let summary: String
	let detail: String
	let status: String
	let page: Page?
	var displayPayload: String = ""
	var displayLanguage: String = ""
	var displayIsError: Bool = false

	init?(json: [String: Any])
	{
		guard let id = json["id"] as? String, let type = json["type"] as? String
		else
		{
			return nil
		}
		self.id = id
		status = json["status"] as? String ?? (type == "webSearch" ? "recorded" : "unknown")
		displayIsError = Self.isFailure(json)
		var page: Page?
		switch type
		{
		case "mcpToolCall", "dynamicToolCall":
			kind = .tool
			let namespace = json["namespace"] as? String ?? "Dynamic tools"
			let server = json["server"] as? String ?? namespace
			let tool = json["tool"] as? String ?? "Tool call"
			provider = Self.providerName(
				server: server,
				tool: tool
			)
			operation = tool.components(separatedBy: ".").last ?? tool
			summary = operation
			if operation == "read_page", status == "completed", !displayIsError,
				json["success"] as? Bool != false,
				json["error"] == nil || json["error"] is NSNull,
				let arguments = json["arguments"] as? [String: Any],
				let pageID = arguments["page_id"] as? String, !pageID.isEmpty
			{
				page = Self.page(
					in: json["result"],
					id: pageID
				)
			}
		case "webSearch":
			kind = .web
			provider = "Web search"
			let action = json["action"] as? [String: Any] ?? [:]
			switch action["type"] as? String ?? "search"
			{
			case "search": operation = "Search"
			case "openPage": operation = "Open"
			case "findInPage": operation = "Find"
			default: operation = "Other"
			}
			let target = action["query"] as? String ?? action["url"] as? String ??
				json["query"] as? String ?? ""
			summary = Self.truncated(
				operation + (target.isEmpty ? "" : ": " + target),
				limit: 512
			)
		case "commandExecution":
			kind = .terminal
			provider = "Terminal"
			operation = "Command"
			summary = Self.truncated(
				json["command"] as? String ?? "Command",
				limit: 512
			)
		default: return nil
		}
		self.page = page
		detail = Self.detailDescription(json)

		let payload = Self.resultPayload(
			json: json,
			isError: displayIsError
		)
		displayPayload = payload.text
		displayLanguage = payload.language
	}

	private static func providerName(
		server: String,
		tool: String
	) -> String
	{
		let isSpaceTool = server.hasPrefix("chatgpt_space") || tool.hasPrefix("chatgpt_space.")
		if isSpaceTool
		{
			return "Space"
		}
		let isAppTool = server == "codex_app" || tool.hasPrefix("codex_app.")
		return isAppTool ? "ChatGPT App Tools" : server
	}

	private static func detailDescription(_ json: [String: Any]) -> String
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

	private static func isFailure(_ json: [String: Any]) -> Bool
	{
		let error = json["error"]
		let result = json["result"] as? [String: Any]
		return json["status"] as? String == "failed" || json["success"] as? Bool == false ||
			(error != nil && !(error is NSNull)) || result?["isError"] as? Bool == true
	}

	private static func resultPayload(
		json: [String: Any],
		isError: Bool
	) -> (text: String, language: String)
	{
		if isError, let error = json["error"], !(error is NSNull)
		{
			return errorPayload(error)
		}
		if let result = json["result"], !(result is NSNull)
		{
			if let object = result as? [String: Any]
			{
				if isError, let content = object["content"] as? [[String: Any]]
				{
					return displayContent(
						content,
						isError: true
					)
				}
				if let structured = object["structuredContent"], !(structured is NSNull)
				{
					return isError ? errorPayload(structured) : displayValue(structured)
				}
				if let content = object["content"] as? [[String: Any]]
				{
					return displayContent(
						content,
						isError: isError
					)
				}
				if let text = object["text"] as? String
				{
					return isError ? errorPayload(text) : displayValue(text)
				}
			}
			return isError ? errorPayload(result) : displayValue(result)
		}
		if let content = json["contentItems"] as? [[String: Any]]
		{
			return displayContent(
				content,
				isError: isError
			)
		}
		if json["type"] as? String == "commandExecution",
			let output = json["aggregatedOutput"] as? String
		{
			return (truncated(
				output,
				limit: 16_384
			), "text")
		}
		if json["type"] as? String == "webSearch"
		{
			if let results = json["results"], !(results is NSNull)
			{
				return displayValue(results)
			}
			if let action = json["action"], !(action is NSNull)
			{
				return displayValue(action)
			}
		}
		return ("", "")
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

	private static func errorPayload(
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
				if let message = object[key], !(message is NSNull)
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

	private static func displayContent(
		_ content: [[String: Any]],
		isError: Bool = false
	) -> (text: String, language: String)
	{
		let texts = content.prefix(24).compactMap
		{
			$0["text"] as? String
		}
		guard !texts.isEmpty
		else
		{
			return ("", "")
		}
		if isError
		{
			var parts: [String] = []
			var remaining = 16_384
			for text in texts
			{
				guard remaining > 0
				else
				{
					break
				}
				let part = errorPayload(text).text
				parts.append(truncated(
					part,
					limit: remaining
				))
				remaining -= min(
					part.count,
					remaining
				)
			}
			if content
				.count > 24 || remaining == 0
			{
				parts.append("[Remaining result content omitted]")
			}
			return (parts.joined(separator: "\n\n"), "text")
		}
		if texts.count == 1, content.count <= 24
		{
			return displayValue(texts[0])
		}
		var decoded: [Any] = []
		var allJSON = true
		for text in texts
		{
			if let value = decodedJSON(text)
			{
				decoded.append(value)
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

	private static func displayValue(_ value: Any) -> (text: String, language: String)
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

	private static func truncated(
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

	private static func page(
		in value: Any?,
		id: String,
		depth: Int = 0
	) -> Page?
	{
		guard depth < 6, let value
		else
		{
			return nil
		}
		if let object = value as? [String: Any]
		{
			let returnedID = object["page_id"] as? String ?? object["pageId"] as? String
			let path = object["url"] as? String ?? object["uri"] as? String
			let knownPageURL = path.flatMap(URL.init(string:)).map
			{
				($0.host == "chatgpt.com" || $0.host == "www.chatgpt.com") && $0.absoluteString
					.contains(id)
			} ?? false
			let title = object["title"] as? String ?? object["name"] as? String ??
				(knownPageURL ? id : nil)
			if returnedID == nil || returnedID == id,
				let title, !title.isEmpty, let path,
				let url = URL(string: path), url.scheme == "https", url.host != nil
			{
				return Page(
					id: id,
					title: truncated(
						title,
						limit: 512
					),
					url: path
				)
			}
			for key in ["structuredContent", "page", "data", "content", "resource", "text"]
			{
				if let page = page(
					in: object[key],
					id: id,
					depth: depth + 1
				)
				{
					return page
				}
			}
		}
		else if let array = value as? [Any]
		{
			for element in array.prefix(24)
			{
				if let page = page(
					in: element,
					id: id,
					depth: depth + 1
				)
				{
					return page
				}
			}
		}
		else if let string = value as? String, string.utf8.count <= 65_536,
				let data = string.data(using: .utf8),
				let object = try? JSONSerialization.jsonObject(with: data)
		{
			return page(
				in: object,
				id: id,
				depth: depth + 1
			)
		}
		return nil
	}
}
