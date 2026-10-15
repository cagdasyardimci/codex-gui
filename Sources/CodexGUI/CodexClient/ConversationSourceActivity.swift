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
			summary = SourceActivityResultPresentation.truncated(
				operation + (target.isEmpty ? "" : ": " + target),
				limit: 512
			)
		case "commandExecution":
			kind = .terminal
			provider = "Terminal"
			operation = "Command"
			summary = SourceActivityResultPresentation.truncated(
				json["command"] as? String ?? "Command",
				limit: 512
			)
		default: return nil
		}
		self.page = page
		detail = SourceActivityResultPresentation.detailDescription(json)

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
			return SourceActivityResultPresentation.errorPayload(error)
		}
		if let result = json["result"], !(result is NSNull)
		{
			if let object = result as? [String: Any]
			{
				if isError, let content = object["content"] as? [[String: Any]]
				{
					return SourceActivityResultPresentation.displayContent(
						content,
						isError: true
					)
				}
				if let structured = object["structuredContent"], !(structured is NSNull)
				{
					return isError
						? SourceActivityResultPresentation.errorPayload(structured)
						: SourceActivityResultPresentation.displayValue(structured)
				}
				if let content = object["content"] as? [[String: Any]]
				{
					return SourceActivityResultPresentation.displayContent(
						content,
						isError: isError
					)
				}
				if let text = object["text"] as? String
				{
					return isError
						? SourceActivityResultPresentation.errorPayload(text)
						: SourceActivityResultPresentation.displayValue(text)
				}
			}
			return isError
				? SourceActivityResultPresentation.errorPayload(result)
				: SourceActivityResultPresentation.displayValue(result)
		}
		if let content = json["contentItems"] as? [[String: Any]]
		{
			return SourceActivityResultPresentation.displayContent(
				content,
				isError: isError
			)
		}
		if json["type"] as? String == "commandExecution",
			let output = json["aggregatedOutput"] as? String
		{
			return SourceActivityResultPresentation.displayOutput(output)
		}
		if json["type"] as? String == "webSearch"
		{
			if let results = json["results"], !(results is NSNull)
			{
				return SourceActivityResultPresentation.displayValue(results)
			}
			if let action = json["action"], !(action is NSNull)
			{
				return SourceActivityResultPresentation.displayValue(action)
			}
		}
		return ("", "")
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
					title: SourceActivityResultPresentation.truncated(
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
