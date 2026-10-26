import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct SettingsMCPFormTests
{
	@Test func addedArgumentSavesAsSeparateLiteralValue() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let form = SettingsMCPForm(
				name: "local",
				configuration: [
					"command": "/usr/bin/tool",
					"args": ["--path"],
					"env": ["TOKEN": "a=b"],
					"env_vars": ["HOME"],
					"cwd": "/project",
				]
			)
			let add = try #require(button(
				"Add argument",
				in: form
			))
			let addAction = try #require(add.action)
			#expect(NSApp.sendAction(
				addAction,
				to: add.target,
				from: add
			))
			let arguments = descendants(form).compactMap
			{
				$0 as? NSTextField
			}.filter
			{
				$0.accessibilityLabel()?.hasPrefix("argument ") == true
			}
			#expect(arguments.count == 2)
			#expect(arguments.allSatisfy
			{
				$0.usesSingleLineMode && $0.constraints.contains
				{
					$0.firstAttribute == .height && $0.constant == 36
				}
			})
			let secondArgument = try #require(arguments.dropFirst().first)
			secondArgument.stringValue = "folder with spaces"

			var saved: [String: Any]?
			form.onSave =
			{
				_, configuration in saved = configuration
			}
			let save = try #require(button(
				"Save",
				in: form
			))
			let saveAction = try #require(save.action)
			#expect(NSApp.sendAction(
				saveAction,
				to: save.target,
				from: save
			))
			let result = try #require(saved)
			#expect(result["args"] as? [String] == ["--path", "folder with spaces"])
			#expect(result["env"] as? [String: String] == ["TOKEN": "a=b"])
			#expect(result["env_vars"] as? [String] == ["HOME"])
			#expect(result["cwd"] as? String == "/project")
		}
	}

	@Test func httpFormKeepsBearerAndEnvironmentHeaderBindingsDistinct() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let form = SettingsMCPForm(
				name: "remote",
				configuration: [
					"url": "https://example.com/mcp",
					"bearer_token_env_var": "OLD_TOKEN",
					"http_headers": ["X-Client": "desktop"],
					"env_http_headers": ["X-Token": "TOKEN_ENV"],
				]
			)
			let fields = descendants(form).compactMap
			{
				$0 as? NSTextField
			}
			let bearer = try #require(fields.first
			{
				$0.accessibilityLabel() == "Bearer token env var"
			})
			let environmentHeader = try #require(fields.first
			{
				$0.accessibilityLabel()?.hasPrefix("environment header value ") == true
			})
			bearer.stringValue = "NEW_TOKEN"
			environmentHeader.stringValue = "NEW_HEADER_ENV"

			var saved: [String: Any]?
			form.onSave =
			{
				_, configuration in saved = configuration
			}
			let save = try #require(button(
				"Save",
				in: form
			))
			let action = try #require(save.action)
			#expect(NSApp.sendAction(
				action,
				to: save.target,
				from: save
			))
			let result = try #require(saved)
			#expect(result["bearer_token_env_var"] as? String == "NEW_TOKEN")
			#expect(result["http_headers"] as? [String: String] ==
				["X-Client": "desktop"])
			#expect(result["env_http_headers"] as? [String: String] ==
				["X-Token": "NEW_HEADER_ENV"])
		}
	}

	private func button(
		_ title: String,
		in view: NSView
	) -> NSButton?
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == title
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}
