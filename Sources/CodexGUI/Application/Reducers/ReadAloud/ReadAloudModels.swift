import Foundation

struct ReadAloudPresentation: Equatable
{
	enum Phase: Equatable
	{
		case idle, starting, speaking
	}
	var canRead = false
	var activeEntryID: String?
	var phase: Phase = .idle
}

struct ReadAloudRequest: Equatable, Sendable
{
	let context: OperationContext
	let entryID: String
	let text: String
}

struct ReadAloudModel
{
	var available = false
	var probe: OperationContext?
	var active: ReadAloudRequest?
	var phase: ReadAloudPresentation.Phase = .idle
	var lastFailure: OperationFailure?
}

enum ReadAloudAction
{
	case requested(ReadAloudRequest)
	case stopRequested
	case availabilityReceived(
		OperationContext,
		Bool
	)
	case speaking(ReadAloudRequest)
	case finished(
		ReadAloudRequest,
		OperationFailure?
	)
}

enum ReadAloudOperation
{
	case probe(OperationContext)
	case play(ReadAloudRequest)
	var context: OperationContext
	{
		switch self
		{
		case .probe(let context): return context
		case .play(let request): return request.context
		}
	}
}

enum ReadAloudBackendEvent: Sendable
{
	case started(version: String)
	case audio(ReadAloudAudioChunk)
	case segmentFinished
	case playbackDrained
	case failed(String)
	case closed
}

/// UTF-8-sized segments stay well below the backend's 1,000 estimated-token speech limit.
enum ReadAloudTextSegments
{
	static func canRead(_ text: String) -> Bool
	{
		!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf8
			.count <= 256 * 1024
	}

	static func make(_ text: String) throws -> [String]
	{
		guard canRead(text)
		else
		{
			throw ReadAloudError.invalidText
		}
		var segments: [String] = []
		var current: [Unicode.Scalar] = []
		var bytes = 0
		for scalar in text.unicodeScalars
		{
			let next = scalar.utf8.count
			if bytes + next > 400
			{
				let boundary = current.lastIndex
				{
					$0.properties.isWhitespace
				}.map
				{
					$0 + 1
				}
				let split = boundary.flatMap
				{
					$0 >= current.count / 2 ? $0 : nil
				} ?? current.count
				segments.append(String(String.UnicodeScalarView(current.prefix(split))))
				current.removeFirst(split)
				bytes = current.reduce(0)
				{
					$0 + $1.utf8.count
				}
			}
			current.append(scalar)
			bytes += next
		}
		if !current.isEmpty
		{
			segments.append(String(String.UnicodeScalarView(current)))
		}

		return segments
	}
}

enum ReadAloudError: Error
{
	case invalidText, unavailable, invalidResponse, eventOverflow, timedOut, sessionClosed
	case backend(String)
}
