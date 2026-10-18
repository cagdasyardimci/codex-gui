import Foundation

struct ConnectionModel
{
	var generation = 0
	var isConnected = false
	var pendingConnection: OperationContext?
	var backendDescription = "Locating Codex…"
	var statusMessage: String?
}
