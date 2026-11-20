import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SharedCodexProfileTests
{
	@Test func sharedCodexProfile() async throws
	{
		let environment = ProcessInfo.processInfo.environment
		let executable = try #require(environment["CODEX_EXECUTABLE"])
		let profile = try #require(environment["CODEX_HOME"])
		let checkout = try #require(environment["CODEX_GUI_QA_SHARED_CHECKOUT"])
		let phase = try #require(environment["CODEX_GUI_QA_SHARED_PHASE"])
		let server = AppServer()
		let backend = SettingsBackend(server: server)
		defer { backend.stop() }

		#expect(AppServer.executableURL()?.path == executable)
		await backend.start()
		try #require(backend.isConnected)
		let context = try await server.settingsRequest("config/read", params: ["includeLayers": true])
		let layers = try #require(context["layers"] as? [[String: Any]])
		let user = try #require(layers.first?["name"] as? [String: Any])
		#expect(user["file"] as? String == profile + "/config.toml")
		let history = try await server.threads(for: URL(fileURLWithPath: checkout))
		#expect(history.map(\.id) == ["history-first", "history-second"])
		let account = try await server.accountStatus()

		if phase == "before"
		{
			#expect(account.email == "appkit@example.invalid")
			#expect(backend.value("model_verbosity") as? String == "low")
			let applied = await backend.write(["model_verbosity": "high"])
			#expect(applied)
			#expect(backend.value("model_verbosity") as? String == "high")
			try await server.logout()
			let signedOut = try await server.accountStatus()
			#expect(signedOut.email == nil)
		}
		else
		{
			#expect(phase == "after")
			#expect(account.email == "tauri@example.invalid")
			#expect(backend.value("model_verbosity") as? String == "medium")
		}
		print("Verified AppKit shared Codex profile \(phase)")
	}
}
