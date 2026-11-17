import Foundation

/// Backend transport used by a private read-aloud session, independent of transcript views.
@MainActor
protocol ReadAloudService: AnyObject
{
	var onReadAloudEvent: ((String, ReadAloudBackendEvent) -> Void)?
	{
		get set
	}
	func readAloudAvailable(in directory: URL) async throws -> Bool
	func createReadAloudThread(in directory: URL) async throws -> String
	func startReadAloudSession(threadID: String) async throws
	func appendReadAloudSpeech(
		threadID: String,
		text: String
	) async throws
	func retireReadAloudThread(threadID: String) async
}
