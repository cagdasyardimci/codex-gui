import Foundation

/// JSONSerialization produces an immutable object graph here. It is never exposed for mutation
/// while crossing to a decoder; application-created values use the typed snapshot below instead.
struct ProtocolJSONPayload: @unchecked Sendable
{
	let value: [String: Any]
}
