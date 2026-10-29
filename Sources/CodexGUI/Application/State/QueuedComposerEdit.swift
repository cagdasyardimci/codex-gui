import Foundation

struct QueuedComposerEdit: Codable, Equatable
{
	let message: QueuedComposerMessage
	let position: Int
}

struct ComposerQueueState: Codable
{
	let messages: [QueuedComposerMessage]
	let edit: QueuedComposerEdit?
}
