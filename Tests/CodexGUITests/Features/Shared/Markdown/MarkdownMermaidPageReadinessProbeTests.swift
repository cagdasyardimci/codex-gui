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

	@Test func pageThatAnswersWithoutReadinessKeepsItsFailure()
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
