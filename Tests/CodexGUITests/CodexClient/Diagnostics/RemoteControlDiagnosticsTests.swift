import Foundation
import Testing

@testable import CodexGUI

@Suite
struct RemoteControlDiagnosticsTests
{
	@Test func latestRelayFailureWinsOverOldConflictsAndUnrelatedLogs() throws
	{
		let target = "codex_app_server_transport::transport::remote_control::websocket"
		let conflict = "WARN \(target): failed to connect: HTTP error: 409 Conflict, "
			+ "body: {\"detail\":\"Remote app server already online\"}"
		#expect(RemoteControlDiagnostics.failure(in: conflict) == .hostAlreadyOnline)
		let log: [String: Any] = [
			"target": target,
			"fields": [
				"message": "failed to connect to app-server remote control websocket",
				"error": "TLS certificate failed; remote_control_token=private-token",
			],
		]
		let data = try JSONSerialization.data(withJSONObject: log)
		let json = try #require(String(
			data: data,
			encoding: .utf8
		))
		let text = conflict + "\n" + json + "\nWARN mcp_client: failed to start another tool"
		guard case .reported(let detail) = RemoteControlDiagnostics.failure(in: text)
		else
		{
			Issue.record("Expected the later relay failure"); return
		}
		#expect(detail.contains("TLS certificate failed"))
		#expect(!detail.contains("private-token"))
		#expect(!detail.contains("another tool"))
	}

	@Test func subprocessLoggingDefaultsPreserveExplicitFiltersAndOtherEnvironment() throws
	{
		let inherited = ["PATH": "/usr/bin", "CUSTOM_VALUE": "keep"]
		let defaults = AppServer.subprocessEnvironment(inherited)
		#expect(defaults["RUST_LOG"]?.contains("remote_control=info") == true)
		#expect(defaults["PATH"] == "/usr/bin")
		#expect(defaults["CUSTOM_VALUE"] == "keep")
		let explicit = ["RUST_LOG": "off", "LOG_FORMAT": "json", "PATH": "/custom/bin"]
		#expect(AppServer.subprocessEnvironment(explicit) == explicit)
	}
}
