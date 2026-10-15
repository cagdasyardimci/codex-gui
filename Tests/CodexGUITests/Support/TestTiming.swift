import Darwin
import Foundation
import Testing

/// Opt-in elapsed-time diagnostics; no file I/O occurs while test bodies execute.
struct TestTiming: TestTrait, SuiteTrait, TestScoping
{
	var isRecursive: Bool
	{
		true
	}

	@TaskLocal private static var currentSpanID: Int?
	private static let workerContextKey = "CodexGUI.TestTiming.WorkerContext"
	private static let recorder: TestTimingRecorder? =
	{
		guard let path = ProcessInfo.processInfo.environment["TEST_TIMING_OUTPUT"], !path.isEmpty
		else
		{
			return nil
		}
		let recorder = TestTimingRecorder(output: URL(fileURLWithPath: path))
		// The standard SwiftPM process writes its buffered trace when it exits.
		// A trace alone is not evidence that the runner completed the full suite.
		atexit
		{
			TestTiming.recorder?.write()
		}
		return recorder
	}()

	func scopeProvider(
		for test: Test,
		testCase: Test.Case?
	) -> Self?
	{
		!test.isSuite ? self : nil
	}

	func provideScope(
		for test: Test,
		testCase: Test.Case?,
		performing function: @Sendable () async throws -> Void
	) async throws
	{
		guard Self.recorder != nil
		else
		{
			try await function()
			return
		}
		let span = Self.begin(
			testCase == nil ? "test.function" : "test.case",
			for: test
		)
		defer
		{
			span.end()
		}
		// The case scope precedes the actor-isolated body. Its entry-to-body gap
		// measures admission delay, not CPU time or every subsequent actor wait.
		try await Self.$currentSpanID.withValue(
			span.context?.id,
			operation: function
		)
	}

	static func begin(
		_ name: String,
		for test: Test? = Test.current,
		detail: String? = nil
	) -> Span
	{
		guard let recorder
		else
		{
			return Span(context: nil)
		}
		let worker = Thread.current.threadDictionary[workerContextKey]
			as? TestTimingRecorder.Context
		return Span(context: recorder.begin(
			name: name,
			parentID: currentSpanID ?? worker?.id,
			testID: test?.id.description ?? worker?.testID,
			detail: detail
		))
	}

	struct Span: Sendable
	{
		fileprivate let context: TestTimingRecorder.Context?

		func mark(_ event: String)
		{
			if let context
			{
				TestTiming.recorder?.append(
					context: context,
					event: event
				)
			}
		}

		func end()
		{
			mark("end")
		}

		/// Carries diagnostic context across a synchronous utility operation, not test assertions.
		func withWorkerContext<Value>(_ operation: () throws -> Value) rethrows -> Value
		{
			guard let context
			else
			{
				return try operation()
			}
			let dictionary = Thread.current.threadDictionary
			let previous = dictionary[TestTiming.workerContextKey]
			dictionary[TestTiming.workerContextKey] = context
			defer
			{
				if let previous
				{
					dictionary[TestTiming.workerContextKey] = previous
				}
				else
				{
					dictionary.removeObject(forKey: TestTiming.workerContextKey)
				}
			}
			return try operation()
		}
	}
}

extension Trait where Self == TestTiming
{
	static var testTiming: Self
	{
		Self()
	}
}

/// The lock protects only IDs and the event buffer; it is never held across an await.
private final class TestTimingRecorder: @unchecked Sendable
{
	struct Context: Sendable
	{
		let id: Int
		let parentID: Int?
		let name: String
		let testID: String?
		let detail: String?
	}

	private struct Event: Encodable
	{
		let spanID: Int
		let parentSpanID: Int?
		let name: String
		let event: String
		let testID: String?
		let detail: String?
		let elapsedSeconds: Double
		let onMainThread: Bool
	}

	private struct Trace: Encodable
	{
		let schemaVersion = 1
		let processID: Int32
		let originUnixSeconds: Double
		let originSystemUptimeSeconds: Double
		let events: [Event]
	}

	private let output: URL
	private let origin = ContinuousClock.now
	private let originUnixSeconds = Date().timeIntervalSince1970
	private let originSystemUptimeSeconds = ProcessInfo.processInfo.systemUptime
	private let lock = NSLock()
	private var nextID = 0
	private var events: [Event] = []

	init(output: URL)
	{
		self.output = output
	}

	func begin(
		name: String,
		parentID: Int?,
		testID: String?,
		detail: String?
	) -> Context
	{
		let context = lock.withLock
		{
			nextID += 1
			return Context(
				id: nextID,
				parentID: parentID,
				name: name,
				testID: testID,
				detail: detail
			)
		}
		append(
			context: context,
			event: "begin"
		)
		return context
	}

	func append(
		context: Context,
		event: String
	)
	{
		let duration = origin.duration(to: .now).components
		let record = Event(
			spanID: context.id,
			parentSpanID: context.parentID,
			name: context.name,
			event: event,
			testID: context.testID,
			detail: context.detail,
			elapsedSeconds: Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
			onMainThread: Thread.isMainThread
		)
		lock.withLock
		{
			events.append(record)
		}
	}

	func write()
	{
		let trace = Trace(
			processID: getpid(),
			originUnixSeconds: originUnixSeconds,
			originSystemUptimeSeconds: originSystemUptimeSeconds,
			events: lock.withLock
			{
				events
			}.sorted
			{
				$0.elapsedSeconds < $1.elapsedSeconds
			}
		)
		do
		{
			try FileManager.default.createDirectory(
				at: output.deletingLastPathComponent(),
				withIntermediateDirectories: true
			)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			try encoder.encode(trace).write(
				to: output,
				options: .atomic
			)
		}
		catch
		{
			let message = "Test timing trace could not be written: \(error)\n"
			FileHandle.standardError.write(Data(message.utf8))
		}
	}
}
