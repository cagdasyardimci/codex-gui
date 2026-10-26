import Testing
@testable import CodexGUI

struct SettingsMCPDraftTests
{
	@Test func editingSTDIOPreservesAdvancedConfigurationAndLiteralArguments() throws
	{
		let draft = SettingsMCPDraft(
			name: "local",
			transport: "STDIO",
			endpoint: "/usr/bin/tool",
			arguments: "--path\nfolder with spaces",
			environment: "TOKEN=a=b",
			headers: "",
			original: [
				"startup_timeout_sec": 20,
				"enabled": false,
				"cwd": "/project"
			]
		)
		let result = try draft.configuration()
		#expect(result["args"] as? [String] == ["--path", "folder with spaces"])
		#expect(result["env"] as? [String: String] == ["TOKEN": "a=b"])
		#expect(result["startup_timeout_sec"] as? Int == 20)
		#expect(result["enabled"] as? Bool == false)
		#expect(result["cwd"] as? String == "/project")
	}

	@Test func switchingTransportRemovesIncompatibleFieldsWithoutDroppingPolicies() throws
	{
		let draft = SettingsMCPDraft(
			name: "remote",
			transport: "HTTP",
			endpoint: "https://example.com/mcp",
			arguments: "",
			environment: "",
			headers: "Authorization=Bearer abc",
			original: [
				"command": "old",
				"args": ["old"],
				"env": ["TOKEN": "old"],
				"env_vars": ["OLD_TOKEN"],
				"cwd": "/old",
				"required": true,
			]
		)
		let result = try draft.configuration()
		#expect(result["command"] == nil)
		#expect(result["args"] == nil)
		#expect(result["env"] == nil)
		#expect(result["env_vars"] == nil)
		#expect(result["cwd"] == nil)
		#expect(result["required"] as? Bool == true)
		#expect(result["http_headers"] as? [String: String] == ["Authorization": "Bearer abc"])
	}

	@Test func invalidPairsAndCredentialURLsAreRejected()
	{
		#expect(throws: (any Error).self)
		{
			try SettingsMCPDraft.pairs(
				"TOKEN=a\nTOKEN=b",
				label: "variable"
			)
		}
		#expect(throws: (any Error).self)
		{
			try SettingsMCPDraft.pairs(
				"missing separator",
				label: "variable"
			)
		}
		#expect(throws: (any Error).self)
		{
			try SettingsMCPDraft(
				name: "remote",
				transport: "HTTP",
				endpoint: "https://user:password@example.com",
				arguments: "",
				environment: "",
				headers: "",
				original: [:]
			).configuration()
		}
	}

	@Test func stdioKeepsEnvironmentValuesDistinctFromPassthroughNames() throws
	{
		let draft = SettingsMCPDraft(
			name: "local",
			transport: "STDIO",
			endpoint: "/usr/bin/tool",
			arguments: "--path\nfolder with spaces",
			environment: "TOKEN=a=b",
			headers: "",
			original: [
				"env_vars": ["OLD"],
				"cwd": "/old",
				"startup_timeout_sec": 20,
			],
			environmentPassthrough: "HOME\nXDG_CONFIG_HOME",
			workingDirectory: " /project "
		)
		let result = try draft.configuration()
		#expect(result["args"] as? [String] == ["--path", "folder with spaces"])
		#expect(result["env"] as? [String: String] == ["TOKEN": "a=b"])
		#expect(result["env_vars"] as? [String] == ["HOME", "XDG_CONFIG_HOME"])
		#expect(result["cwd"] as? String == "/project")
		#expect(result["startup_timeout_sec"] as? Int == 20)
	}

	@Test func httpRoundTripWritesAndClearsOptionalAuthAndEnvironmentHeaders() throws
	{
		let original: [String: Any] = [
			"url": "https://example.com/mcp",
			"bearer_token_env_var": "OLD",
			"env_http_headers": ["X-Token": "OLD_TOKEN"],
			"auth": "managed",
		]
		let updated = try SettingsMCPDraft(
			name: "remote",
			transport: "HTTP",
			endpoint: "https://example.com/mcp",
			arguments: "",
			environment: "",
			headers: "X-Client=desktop",
			original: original,
			bearerTokenEnvironmentVariable: " MCP_TOKEN ",
			environmentHeaders: "X-Token=TOKEN_ENV"
		).configuration()
		#expect(updated["bearer_token_env_var"] as? String == "MCP_TOKEN")
		#expect(updated["env_http_headers"] as? [String: String] ==
			["X-Token": "TOKEN_ENV"])
		#expect(updated["http_headers"] as? [String: String] == ["X-Client": "desktop"])
		#expect(updated["auth"] as? String == "managed")

		let cleared = try SettingsMCPDraft(
			name: "remote",
			transport: "HTTP",
			endpoint: "https://example.com/mcp",
			arguments: "",
			environment: "",
			headers: "",
			original: original,
			bearerTokenEnvironmentVariable: "",
			environmentHeaders: ""
		).configuration()
		#expect(cleared["bearer_token_env_var"] == nil)
		#expect(cleared["env_http_headers"] == nil)
		#expect(cleared["auth"] as? String == "managed")
	}

	@Test func clearingSTDIOOptionalFieldsRemovesTheirConfigurationKeys() throws
	{
		let result = try SettingsMCPDraft(
			name: "local",
			transport: "STDIO",
			endpoint: "/usr/bin/tool",
			arguments: "",
			environment: "",
			headers: "",
			original: [
				"args": ["old"],
				"env": ["TOKEN": "old"],
				"env_vars": ["HOME"],
				"cwd": "/old",
				"enabled": false,
				"auth": "http-only",
				"oauth_resource": "https://example.com",
			],
			environmentPassthrough: "",
			workingDirectory: ""
		).configuration()
		#expect(result["args"] == nil)
		#expect(result["env"] == nil)
		#expect(result["env_vars"] == nil)
		#expect(result["cwd"] == nil)
		#expect(result["auth"] == nil)
		#expect(result["oauth_resource"] == nil)
		#expect(result["enabled"] as? Bool == false)
	}
}
