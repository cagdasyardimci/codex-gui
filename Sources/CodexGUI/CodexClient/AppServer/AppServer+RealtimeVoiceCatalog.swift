import Foundation

extension AppServer
{
	static let realtimeAudioVersion = "v3"

	static func realtimeAudioVoices(from response: [String: Any]) throws -> [String]
	{
		guard let catalog = response["voices"] as? [String: Any]
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid voice catalog.")
		}
		guard let versionVoices = catalog[realtimeAudioVersion]
		else
		{
			return []
		}
		guard let voices = versionVoices as? [String]
		else
		{
			throw AppServerError.protocolError("Codex returned an invalid voice catalog.")
		}
		return voices
	}

	static func realtimeAudioDefault(from response: [String: Any]) -> String?
	{
		let catalog = response["voices"] as? [String: Any]
		// App-server 0.169 uses defaultV1 for V3 but does not publish defaultV3.
		return catalog?["defaultV3"] as? String ?? catalog?["defaultV1"] as? String
	}

	func realtimeVoiceForSession(in directory: URL) async throws -> String
	{
		guard let config = try await realtimeVoiceConfiguration(in: directory)
		else
		{
			throw ReadAloudError.unavailable
		}
		let response = try await request(
			"thread/realtime/listVoices",
			params: [:]
		)
		let supported = try Self.realtimeAudioVoices(from: response)
		let configured = (config["realtime"] as? [String: Any])?["voice"] as? String
		// Send the resolved value so a loaded thread cannot reuse a stale voice override.
		guard let voice = configured ?? Self.realtimeAudioDefault(from: response),
				supported.contains(voice)
		else
		{
			throw ReadAloudError.unavailable
		}
		return voice
	}
}
