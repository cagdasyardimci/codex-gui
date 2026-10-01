import Foundation

enum AppServerError: LocalizedError
{
	case executableMissing
	case incompatibleVersion(String)
	case disconnected
	case protocolError(String)
	case requestRejected(String)
	case invalidInteraction(String)
	case requestTimedOut(String)

	var errorDescription: String?
	{
		switch self
		{
		case .executableMissing: "Codex CLI was not found. Install it and restart the app."
		case .incompatibleVersion(let version):
			"Codex CLI \(version) is older than the supported app-server protocol (0.153.2)."
		case .disconnected: "Codex app-server disconnected. Reconnect to refresh state."
		case .protocolError(let message), .requestRejected(let message),
				.invalidInteraction(let message): message
		case .requestTimedOut(let method):
			if method == "turn/start"
			{
				"Codex did not answer turn/start. Reopen the conversation to check whether the "
					+ "turn began before sending again."
			}
			else if method == "turn/steer"
			{
				"Codex did not answer turn/steer. Reopen the conversation to check whether the "
					+ "steering was accepted before trying again."
			}
			else
			{
				"Codex did not answer \(method). Reconnect and try again."
			}
		}
	}
}
