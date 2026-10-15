import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct GitNavigatorTransitionTests
{
	@Test(.timeLimit(.minutes(1)))
	func widthFollowsBothTargetsAndReversalDropsSupersededCompletion() async throws
	{
		let root = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 500,
			height: 200
		))
		let host = NSView()
		root.addSubview(host)
		host.translatesAutoresizingMaskIntoConstraints = false
		let width = host.widthAnchor.constraint(equalToConstant: 280)
		NSLayoutConstraint.activate([
			width,
			host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
			host.topAnchor.constraint(equalTo: root.topAnchor),
			host.heightAnchor.constraint(equalToConstant: 100),
		])
		let clock = AnimationClock()
		defer
		{
			clock.advance(to: 1)
		}
		var ticks = clock.ticks.makeAsyncIterator()
		let transition = GitNavigatorTransition(
			widthConstraint: width,
			layoutView: root,
			now:
			{
				clock.now
			},
			sleep:
			{
				_ in await clock.sleep()
			},
			shouldReduceMotion:
			{
				false
			}
		)
		transition.setVisible(
			false,
			animated: false
		)
		#expect(width.constant == 0)
		transition.setVisible(
			true,
			animated: false
		)
		#expect(width.constant == 280)
		transition.setVisible(
			false,
			animated: false
		)
		#expect(width.constant == 0)

		var supersededCompletions = 0
		var finalCompletions = 0
		let (completed, completion) = AsyncStream<Void>.makeStream()
		defer
		{
			completion.finish()
		}
		var completions = completed.makeAsyncIterator()
		transition.setVisible(
			true,
			completion:
			{
				supersededCompletions += 1
			}
		)
		// Hold each animation frame until the test advances its clock; a busy main
		// actor cannot skip the intermediate width or finish before reversal.
		_ = await ticks.next()
		clock.advance(to: 0.08)
		_ = await ticks.next()
		#expect(transition.currentWidth > 0 && transition.currentWidth < 280)
		transition.setVisible(
			false,
			completion:
			{
				finalCompletions += 1
				completion.yield(())
			}
		)
		_ = await ticks.next()
		clock.advance(to: 0.5)
		_ = await completions.next()
		#expect(abs(transition.currentWidth) < 0.5)
		#expect(supersededCompletions == 0)
		#expect(finalCompletions == 1)
		#expect(!transition.isAnimating)
	}

	@Test func reduceMotionCompletesBothTargetsWithoutStartingAnimation()
	{
		let view = NSView()
		let width = view.widthAnchor.constraint(equalToConstant: 280)
		let transition = GitNavigatorTransition(
			widthConstraint: width,
			layoutView: view,
			sleep:
			{
				_ in Issue.record("Reduced motion must not schedule animation frames")
			},
			shouldReduceMotion:
			{
				true
			}
		)
		var completions: [Bool] = []
		for visible in [false, true, false]
		{
			transition.setVisible(
				visible,
				completion:
				{
					completions.append(visible)
				}
			)
			#expect(width.constant == (visible ? 280 : 0))
			#expect(!transition.isAnimating)
		}
		#expect(completions == [false, true, false])
	}

	@Test(.timeLimit(.minutes(1)))
	func enablingReduceMotionFinishesAnAlreadyStartedAnimation() async
	{
		let view = NSView()
		let width = view.widthAnchor.constraint(equalToConstant: 0)
		let clock = AnimationClock()
		defer
		{
			clock.advance(to: 1)
		}
		var reduceMotion = false
		let transition = GitNavigatorTransition(
			widthConstraint: width,
			layoutView: view,
			now:
			{
				clock.now
			},
			sleep:
			{
				_ in await clock.sleep()
			},
			shouldReduceMotion:
			{
				reduceMotion
			}
		)
		let (completed, completion) = AsyncStream<Void>.makeStream()
		defer
		{
			completion.finish()
		}
		var ticks = clock.ticks.makeAsyncIterator()
		var completions = completed.makeAsyncIterator()
		var completionCount = 0
		transition.setVisible(
			true,
			completion:
			{
				completionCount += 1
				completion.yield(())
			}
		)
		_ = await ticks.next()
		#expect(transition.isAnimating)
		#expect(completionCount == 0)
		reduceMotion = true
		clock.advance(to: 0.08)
		_ = await completions.next()
		#expect(width.constant == 280)
		#expect(completionCount == 1)
		#expect(!transition.isAnimating)
	}

	@MainActor
	private final class AnimationClock
	{
		var now: TimeInterval = 0
		let ticks: AsyncStream<Void>
		private let continuation: AsyncStream<Void>.Continuation
		private var sleepers: [CheckedContinuation<Void, Never>] = []

		init()
		{
			(ticks, continuation) = AsyncStream<Void>.makeStream()
		}

		func sleep() async
		{
			await withCheckedContinuation
			{
				sleepers.append($0)
				continuation.yield(())
			}
		}

		func advance(to time: TimeInterval)
		{
			now = time
			let pending = sleepers
			sleepers.removeAll()
			for sleeper in pending
			{
				sleeper.resume()
			}
		}
	}
}
