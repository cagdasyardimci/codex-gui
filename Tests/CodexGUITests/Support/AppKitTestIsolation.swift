import Testing

/// MainActor serializes operations, but asynchronous tests can overlap across awaits.
/// Reserve application-wide UI state across suspension and cleanup only where tests use it.
/// Fixture-owned views, stores and asynchronous work do not need this permit.
struct AppKitTestIsolation: TestTrait, SuiteTrait, TestScoping
{
	var isRecursive: Bool
	{
		true
	}

	func scopeProvider(
		for test: Test,
		testCase: Test.Case?
	) -> Self?
	{
		// Wait before case time limits start, and avoid nested acquisition by suites or cases.
		!test.isSuite && testCase == nil ? self : nil
	}

	func provideScope(
		for test: Test,
		testCase: Test.Case?,
		performing function: @Sendable () async throws -> Void
	) async throws
	{
		try await Self.perform(for: test)
		{
			// Parameterized cases must also share the protected function's single permit.
			try await ParallelizationTrait.serialized.provideScope(
				for: test,
				testCase: nil,
				performing: function
			)
		}
	}

	/// Prepare fixture-owned state first; reserve AppKit only across native UI work and cleanup.
	/// Shares the trait's permit, so scoped presentation still excludes protected test functions.
	@MainActor
	static func perform(
		for test: Test? = Test.current,
		_ function: @MainActor @Sendable () async throws -> Void
	) async throws
	{
		let timing = TestTiming.begin(
			"appkit.permit",
			for: test
		)
		defer
		{
			timing.end()
		}
		try await AppKitTestPermit.shared.run(
			timing: timing,
			function
		)
	}
}

extension Trait where Self == AppKitTestIsolation
{
	static var appKitIsolation: Self
	{
		Self()
	}
}

// Claim the permit on the same actor as native work. A separate actor could claim it,
// then hold it idle while the protected closure waited to reach the main actor.
@MainActor
private final class AppKitTestPermit
{
	static let shared = AppKitTestPermit()
	private var available = true
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func run(
		timing: TestTiming.Span,
		_ function: @MainActor @Sendable () async throws -> Void
	) async throws
	{
		try Task.checkCancellation()
		timing.mark("requested")
		if available
		{
			available = false
		}
		else
		{
			await withCheckedContinuation
			{
				waiters.append($0)
			}
		}
		timing.mark("acquired")
		// Canceled waiters still take and return their permit, without executing the test body.
		// Release only after the protected body's cleanup, including when it throws.
		defer
		{
			timing.mark("released")
			if waiters.isEmpty
			{
				available = true
			}
			else
			{
				waiters.removeFirst().resume()
			}
		}
		try Task.checkCancellation()
		try await function()
	}
}
