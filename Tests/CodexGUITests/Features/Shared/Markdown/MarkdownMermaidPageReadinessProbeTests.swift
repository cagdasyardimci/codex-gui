import Testing

@testable import CodexGUI

@Suite @MainActor
struct MarkdownMermaidPageReadinessProbeTests
{
	@Test func pageDeadlineAcceptsReadinessDeliveredAfterTheNativeTimer()
	{
		var guestReply: (@MainActor (Bool) -> Void)?
		var outcomes: [Bool] = []
		let probe = MarkdownMermaidPageReadinessProbe(
			probe:
			{
				guestReply = $0
			},
			completion:
			{
				outcomes.append($0)
			}
		)
		probe.start()
		#expect(outcomes.isEmpty)
		guestReply?(true)
		#expect(outcomes == [true])
		guestReply?(false)
		#expect(outcomes == [true])
	}

	@Test func loadingSnapshotDoesNotRejectNavigationThatFinishesWithinTheWatchdog()
	{
		var outcomes: [Bool] = []
		let probe = MarkdownMermaidPageReadinessProbe(
			probe:
			{
				$0(false)
			},
			completion:
			{
				outcomes.append($0)
			}
		)
		probe.start()
		#expect(outcomes.isEmpty)
		// WKNavigationDelegate.didFinish can arrive after the snapshot of the loading page.
		probe.confirmReadiness()
		#expect(outcomes == [true])
		probe.confirmReadiness()
		#expect(outcomes == [true])
	}

	@Test func pageThatNeverBecomesReadyStillHitsTheOriginalWatchdog() async
	{
		var outcomes: [Bool] = []
		var probe: MarkdownMermaidPageReadinessProbe?
		let ready = await withCheckedContinuation
		{
			continuation in
			probe = MarkdownMermaidPageReadinessProbe(
				maximumWait: .milliseconds(1),
				probe:
				{
					$0(false)
				},
				completion:
				{
					outcomes.append($0)
					continuation.resume(returning: $0)
				}
			)
			probe?.start()
			#expect(outcomes.isEmpty)
		}
		#expect(!ready)
		#expect(outcomes == [false])
		probe?.confirmReadiness()
		#expect(outcomes == [false])
	}

	@Test func finishedOrInvalidatedNavigationIgnoresLateProbeReplies()
	{
		var guestReply: (@MainActor (Bool) -> Void)?
		var outcomes: [Bool] = []
		let probe = MarkdownMermaidPageReadinessProbe(
			probe:
			{
				guestReply = $0
			},
			completion:
			{
				outcomes.append($0)
			}
		)
		probe.start()
		// Session.finish cancels this probe for completion, cancellation and navigation failure.
		probe.cancel()
		probe.confirmReadiness()
		guestReply?(true)
		guestReply?(false)
		#expect(outcomes.isEmpty)
	}

	@Test func unresponsiveGuestHitsTheProbeDeadlineAndCannotCompleteAgain() async
	{
		var guestReply: (@MainActor (Bool) -> Void)?
		var outcomes: [Bool] = []
		var probe: MarkdownMermaidPageReadinessProbe?
		let ready = await withCheckedContinuation
		{
			continuation in
			probe = MarkdownMermaidPageReadinessProbe(
				maximumWait: .milliseconds(1),
				probe:
				{
					guestReply = $0
				},
				completion:
				{
					outcomes.append($0)
					continuation.resume(returning: $0)
				}
			)
			probe?.start()
		}
		#expect(!ready)
		#expect(outcomes == [false])
		guestReply?(true)
		#expect(outcomes == [false])
		probe?.cancel()
	}
}
