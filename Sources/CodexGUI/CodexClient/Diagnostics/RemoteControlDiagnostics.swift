import Foundation

/// Extracts a relay failure without confusing other backend warnings with host availability.
enum RemoteControlDiagnostics
{
	static func failure(in stderr: String) -> RemoteControlConnectionFailure?
	{
		let safeText = BackendDiagnosticsBuffer.displaySafeText(stderr)
		for line in safeText.components(separatedBy: .newlines).reversed()
		{
			var detail: String?
			if let data = line.data(using: .utf8),
				let log = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				let target = log["target"] as? String,
				target.contains("::remote_control"),
				let fields = log["fields"] as? [String: Any],
				let message = fields["message"] as? String,
				isFailure(message)
			{
				detail = fields["error"] as? String ?? fields["err"] as? String ?? message
			}
			else if line.contains("::remote_control"), isFailure(line)
			{
				detail = line
			}
			guard let detail
			else
			{
				continue
			}
			if detail.localizedCaseInsensitiveContains("Remote app server already online")
			{
				return .hostAlreadyOnline
			}
			return .reported(String(BackendDiagnosticsBuffer.displaySafeText(detail).prefix(1200)))
		}
		return nil
	}

	private static func isFailure(_ text: String) -> Bool
	{
		let lower = text.lowercased()
		return lower.contains("failed") || lower.contains("disconnected") || lower.contains("error")
	}
}
