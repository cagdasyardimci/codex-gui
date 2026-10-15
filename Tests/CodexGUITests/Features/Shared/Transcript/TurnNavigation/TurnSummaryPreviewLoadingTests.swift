import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct TurnSummaryPreviewLoadingTests
{
	@Test(.timeLimit(.minutes(1)))
	func hoveringDebouncesPreviewLoadingAndDismissalCancelsIt() async throws
	{
		let clock = PreviewDebounceClock()
		let rail = TurnNavigationRail(previewDebounceSleep: clock.sleep)
		defer
		{
			rail.dismissPreview()
			clock.finish()
		}
		var registrations = clock.registrations.makeAsyncIterator()
		let first = ConversationTurnSummary(
			turnID: "first",
			entryID: "first:reference",
			title: "Earlier turn",
			reply: "",
			isContentLoaded: false
		)
		let last = ConversationTurnSummary(
			turnID: "last",
			entryID: "last:reference",
			title: "Earlier turn",
			reply: "",
			isContentLoaded: false
		)
		var loaded: [String] = []
		rail.onLoadTurnPreview =
		{
			loaded.append($0)
		}
		rail.requestTurnPreview(first)
		let firstLoad = try #require(rail.hoverLoadTask)
		try #require(await registrations.next() == .milliseconds(75))
		clock.advance(by: .milliseconds(74))
		#expect(clock.pendingCount == 1)
		#expect(loaded.isEmpty)
		// Replace an already sleeping request just before its deadline.
		rail.requestTurnPreview(last)
		let lastLoad = try #require(rail.hoverLoadTask)
		try #require(await registrations.next() == .milliseconds(75))
		await firstLoad.value
		#expect(clock.pendingCount == 1)
		clock.advance(by: .milliseconds(74))
		#expect(clock.pendingCount == 1)
		#expect(loaded.isEmpty)
		clock.advance(by: .milliseconds(1))
		await lastLoad.value
		#expect(loaded == ["last"])
		#expect(clock.pendingCount == 0)
		rail.requestTurnPreview(first)
		let canceledLoad = try #require(rail.hoverLoadTask)
		try #require(await registrations.next() == .milliseconds(75))
		rail.dismissPreview()
		await canceledLoad.value
		#expect(clock.pendingCount == 0)
		clock.advance(by: .milliseconds(75))
		#expect(loaded == ["last"])
	}

	@Test func previewSkeletonIsReplacedByCachedContentWithoutLoadingTheTranscript() throws
	{
		_ = NSApplication.shared
		let reference = ConversationTurnReference(
			id: "turn",
			status: "completed"
		)
		let unloaded = ConversationTurnSummary.navigation(
			references: [reference],
			loaded: []
		)
		let preview = TurnSummaryPreview(
			summary: unloaded[0],
			bookmarked: false
		)
		#expect(preview.isLoading)
		#expect(preview.cardHeight == 100)
		let skeleton = try #require(preview.layer?.sublayers?.first)
		let stack = try #require(preview.subviews.first as? NSStackView)
		let header = try #require(stack.arrangedSubviews.first as? NSStackView)
		let title = try #require(header.arrangedSubviews.first as? NSTextField)
		let bookmark = try #require(header.arrangedSubviews.last as? NSButton)
		let reply = try #require(stack.arrangedSubviews.last as? NSTextField)
		#expect(!skeleton.isHidden)
		#expect(title.isHidden && reply.isHidden && bookmark.isHidden)
		#expect(preview.accessibilityLabel() == "Loading turn preview")
		let cached = ConversationTurnPreview(
			turnID: "turn",
			entryID: "turn:request",
			title: "The request",
			reply: "The reply"
		)
		let summaries = ConversationTurnSummary.navigation(
			references: [reference],
			loaded: [],
			cached: [cached]
		)
		preview.render(summaries[0])
		#expect(!preview.isLoading)
		#expect(title.stringValue == "The request")
		#expect(reply.stringValue == "The reply")
		#expect(!title.isHiddenOrHasHiddenAncestor && !reply.isHiddenOrHasHiddenAncestor)
		#expect(skeleton.isHidden)
		#expect(skeleton.animationKeys()?.isEmpty != false)
		#expect(!bookmark.isHiddenOrHasHiddenAncestor && bookmark.isEnabled)
		#expect(bookmark.accessibilityLabel() == "Bookmark turn")
		#expect(preview.accessibilityLabel() == "Turn preview")
		#expect(!summaries[0].isContentLoaded)
		#expect(summaries[0].isPreviewLoaded)
		#expect(summaries[0].reply == "The reply")
		#expect(summaries[0].entryID == "turn:reference")
	}

}

@MainActor
private final class PreviewDebounceClock
{
	private struct Sleeper
	{
		let deadline: Duration
		let continuation: CheckedContinuation<Void, Error>
	}

	let registrations: AsyncStream<Duration>
	private let registrationContinuation: AsyncStream<Duration>.Continuation
	private var now = Duration.zero
	private var sleepers: [UUID: Sleeper] = [:]

	var pendingCount: Int
	{
		sleepers.count
	}

	init()
	{
		let stream = AsyncStream<Duration>.makeStream()
		registrations = stream.stream
		registrationContinuation = stream.continuation
	}

	func sleep(for duration: Duration) async throws
	{
		try Task.checkCancellation()
		let id = UUID()
		try await withTaskCancellationHandler
		{
			try await withCheckedThrowingContinuation
			{
				(continuation: CheckedContinuation<Void, Error>) in
				guard !Task.isCancelled
				else
				{
					continuation.resume(throwing: CancellationError())
					return
				}
				sleepers[id] = Sleeper(
					deadline: now + duration,
					continuation: continuation
				)
				registrationContinuation.yield(duration)
			}
		}
		onCancel:
		{
			Task
			{
				@MainActor in
				self.sleepers.removeValue(forKey: id)?.continuation
					.resume(throwing: CancellationError())
			}
		}
	}

	func advance(by duration: Duration)
	{
		now += duration
		let ready = sleepers.filter
		{
			$0.value.deadline <= now
		}
		for (id, sleeper) in ready
		{
			sleepers.removeValue(forKey: id)
			sleeper.continuation.resume()
		}
	}

	func finish()
	{
		registrationContinuation.finish()
		let pending = sleepers.values
		sleepers.removeAll()
		for sleeper in pending
		{
			sleeper.continuation.resume(throwing: CancellationError())
		}
	}
}
