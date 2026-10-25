import Foundation

extension AppServer
{
	func remoteControlStatus() async throws -> RemoteControlStatus
	{
		try decodeRemoteControl(await request(
			"remoteControl/status/read",
			params: [:]
		))
	}

	func setRemoteControlEnabled(_ enabled: Bool) async throws -> RemoteControlStatus
	{
		try decodeRemoteControl(await request(
			enabled ? "remoteControl/enable" : "remoteControl/disable",
			params: ["ephemeral": true]
		))
	}

	func startRemoteControlPairing() async throws -> RemoteControlPairing
	{
		let pairing: RemoteControlPairing = try decodeRemoteControl(await request(
			"remoteControl/pairing/start",
			params: ["manualCode": true]
		))
		guard !pairing.pairingCode.isEmpty, !pairing.environmentId.isEmpty,
				let code = pairing.manualPairingCode, !code.isEmpty
		else
		{
			throw AppServerError.protocolError("Codex did not return a manual pairing code.")
		}
		return pairing
	}

	func remoteControlPairingClaimed(_ pairing: RemoteControlPairing) async throws -> Bool
	{
		struct Status: Decodable
		{
			let claimed: Bool
		}
		let status: Status = try decodeRemoteControl(await request(
			"remoteControl/pairing/status",
			params: ["pairingCode": pairing.pairingCode]
		))
		return status.claimed
	}

	func remoteControlClients(environmentID: String) async throws -> [RemoteControlClient]
	{
		struct Page: Decodable
		{
			let data: [RemoteControlClient]
			let nextCursor: String?
		}
		var clients: [RemoteControlClient] = []
		var pageCount = 0
		var cursor: String?
		var tracker = PaginationCursorTracker(
			repeatedCursorMessage: "Codex repeated the device list cursor."
		)
		repeat
		{
			pageCount += 1
			guard pageCount <= 20
			else
			{
				throw AppServerError.protocolError("Codex returned too many device list pages.")
			}
			var params: [String: Any] = ["environmentId": environmentID, "limit": 100]
			if let cursor
			{
				params["cursor"] = cursor
			}
			let page: Page = try decodeRemoteControl(await request(
				"remoteControl/client/list",
				params: params
			))
			guard page.data.allSatisfy(
				{
					!$0.clientId.isEmpty
				}
			),
				clients.count + page.data.count <= 1000
			else
			{
				throw AppServerError.protocolError("Codex returned an invalid device list.")
			}
			clients += page.data
			cursor = try tracker.advance(to: page.nextCursor)
		}
		while cursor != nil
		var seen = Set<String>()
		return clients.filter
		{
			seen.insert($0.clientId).inserted
		}
	}

	func revokeRemoteControlClient(
		environmentID: String,
		clientID: String
	) async throws
	{
		_ = try await request(
			"remoteControl/client/revoke",
			params: ["environmentId": environmentID, "clientId": clientID]
		)
	}

	func decodeRemoteControl<T: Decodable>(_ json: [String: Any]) throws -> T
	{
		do
		{
			return try JSONDecoder().decode(
				T.self,
				from: JSONSerialization.data(withJSONObject: json)
			)
		}
		catch
		{
			// Decoder descriptions can contain pairing secrets from malformed responses.
			throw AppServerError.protocolError("Codex returned invalid remote access information.")
		}
	}
}
