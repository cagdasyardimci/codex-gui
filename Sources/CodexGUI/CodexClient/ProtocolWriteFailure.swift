import Foundation

struct ProtocolWriteFailure: LocalizedError
{
	let cause: Error
	let mayHaveBeenSent: Bool
	let requiresDisconnect: Bool

	var errorDescription: String?
	{
		cause.localizedDescription
	}
}
