import Foundation

struct SettingsMCPDraft
{
	var name: String
	var transport: String
	var endpoint: String
	var arguments: String
	var environment: String
	var headers: String
	var original: [String: Any]
	var environmentPassthrough: String? = nil
	var workingDirectory: String? = nil
	var bearerTokenEnvironmentVariable: String? = nil
	var environmentHeaders: String? = nil

	func configuration() throws -> [String: Any]
	{
		guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			throw AppServerError.requestRejected("Enter a server name.")
		}
		guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else
		{
			throw AppServerError
				.requestRejected(transport == "HTTP" ? "Enter a server URL." : "Enter a command.")
		}
		var config = original
		if transport == "HTTP"
		{
			guard let url = URL(string: endpoint), ["https", "http"].contains(url.scheme ?? ""),
					let host = url.host, !host.isEmpty, url.user == nil, url.password == nil
			else
			{
				throw AppServerError
					.requestRejected("Enter an HTTP or HTTPS URL without credentials.")
			}
			for key in ["command", "args", "env", "env_vars", "cwd"]
			{
				config.removeValue(forKey: key)
			}
			config["url"] = endpoint
			let parsedHeaders = try Self.pairs(
				headers,
				label: "header"
			)
			config["http_headers"] = parsedHeaders.isEmpty ? nil : parsedHeaders
			if let bearerTokenEnvironmentVariable
			{
				let value = bearerTokenEnvironmentVariable.trimmingCharacters(
					in: .whitespacesAndNewlines
				)
				config["bearer_token_env_var"] = value.isEmpty ? nil : value
			}
			if let environmentHeaders
			{
				let pairs = try Self.pairs(
					environmentHeaders,
					label: "environment header"
				)
				config["env_http_headers"] = pairs.isEmpty ? nil : pairs
			}
		}
		else
		{
			for key in [
				"url",
				"auth",
				"oauth",
				"scopes",
				"oauth_resource",
				"http_headers",
				"env_http_headers",
				"bearer_token_env_var",
			]
			{
				config.removeValue(forKey: key)
			}
			config["command"] = endpoint
			let parsedArguments = arguments.components(separatedBy: .newlines).filter
			{
				!$0.isEmpty
			}
			config["args"] = parsedArguments.isEmpty ? nil : parsedArguments
			let parsedEnvironment = try Self.pairs(
				environment,
				label: "environment variable"
			)
			config["env"] = parsedEnvironment.isEmpty ? nil : parsedEnvironment
			if let environmentPassthrough
			{
				let values = environmentPassthrough.components(separatedBy: .newlines)
					.map
					{
						$0.trimmingCharacters(in: .whitespacesAndNewlines)
					}.filter
					{
						!$0.isEmpty
					}
				config["env_vars"] = values.isEmpty ? nil : values
			}
			if let workingDirectory
			{
				let value = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
				config["cwd"] = value.isEmpty ? nil : value
			}
		}
		return config
	}

	static func pairs(
		_ text: String,
		label: String
	) throws -> [String: String]
	{
		var result: [String: String] = [:]
		for line in text.components(separatedBy: .newlines) where !line.isEmpty
		{
			guard let split = line.firstIndex(of: "="), split != line.startIndex
			else
			{
				throw AppServerError
					.requestRejected("Enter each \(label) as NAME=value on its own line.")
			}
			let name = String(line[..<split])
			guard result[name] == nil
			else
			{
				throw AppServerError.requestRejected("Duplicate \(label): \(name).")
			}
			result[name] = String(line[line.index(after: split)...])
		}
		return result
	}
}
