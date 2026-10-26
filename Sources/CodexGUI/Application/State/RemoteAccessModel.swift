import Foundation

struct RemoteControlStatus: Equatable, Sendable, Decodable
{
	enum Connection: String, Decodable, Sendable
	{
		case disabled, connecting, connected, errored
	}
	let status: Connection
	let serverName: String
	let installationId: String
	let environmentId: String?
}

struct RemoteControlPairing: Equatable, Sendable, Decodable
{
	let pairingCode: String
	let manualPairingCode: String?
	let environmentId: String
	let expiresAt: Int64

	func isValid(at date: Date) -> Bool
	{
		Double(expiresAt) > date.timeIntervalSince1970
	}
}

struct RemoteControlClient: Equatable, Sendable, Decodable
{
	let clientId: String
	let displayName: String?
	let deviceType: String?
	let platform: String?
	let osVersion: String?
	let deviceModel: String?
	let appVersion: String?
	let lastSeenAt: Int64?
}

enum RemoteAccessCommand: Equatable
{
	case refresh
	case setEnabled(Bool)
	case pair
	case revoke(
		environmentID: String,
		clientID: String
	)
	case clearPairing
	case expirePairing
}

struct RemoteAccessOperation: Equatable
{
	let context: OperationContext
	let command: RemoteAccessCommand
	let statusRevision: Int
	var pairing: RemoteControlPairing? = nil
}

enum RemoteControlConnectionFailure: Equatable, Sendable
{
	case hostAlreadyOnline
	case reported(String)
}

struct RemoteAccessUpdate
{
	var status: RemoteControlStatus?
	var pairing: RemoteControlPairing?
	var clients: [RemoteControlClient]?
	var environmentID: String?
	var pairingClaimed = false
	var connectionFailure: RemoteControlConnectionFailure?
	var error: String?
}

struct RemoteAccessModel: Equatable
{
	var desiredEnabled = false
	var status: RemoteControlStatus?
	var pairing: RemoteControlPairing?
	var clients: [RemoteControlClient] = []
	var pending: RemoteAccessOperation?
	var error: String?
	var statusRevision = 0
	var connectionFailure: RemoteControlConnectionFailure?
}

enum RemoteAccessAction
{
	case requested(
		OperationContext,
		RemoteAccessCommand,
		Date
	)
	case finished(
		RemoteAccessOperation,
		OperationResult<RemoteAccessUpdate>,
		Date
	)
	case statusObserved(
		OperationContext,
		RemoteControlStatus
	)
}
