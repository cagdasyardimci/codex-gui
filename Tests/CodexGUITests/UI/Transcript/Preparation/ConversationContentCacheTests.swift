import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ConversationContentCacheTests
{
	@Test func cancellationAfterParsingRejectsNativePreparation() async throws
	{
		let source = "```swift\nlet value = 42\n```"
		let parsed = AsyncStream<Void>.makeStream()
		let release = DispatchSemaphore(value: 0)
		defer
		{
			release.signal()
			parsed.continuation.finish()
		}
		let cache = ConversationContentCache
		{
			body, markdown, softBreaks in
			let result = MarkdownContentParser.parse(
				body,
				markdown: markdown,
				preserveSoftBreaks: softBreaks
			)
			if body == source
			{
				parsed.continuation.yield(())
				release.wait()
			}
			return result
		}
		let task = Task.detached
		{
			try await cache.content(
				body: source,
				markdown: true
			)
		}
		for await _ in parsed.stream
		{
			break
		}
		task.cancel()
		release.signal()
		do
		{
			_ = try await task.value
			Issue.record("Canceled preparation must stop before native content construction")
		}
		catch is CancellationError
		{
		}
		let content = try await cache.content(
			body: "Current response",
			markdown: true
		)
		#expect(content.attributedString.string == "Current response")
	}

	@Test func waitForRenderingFollowsSupersededPreparation() async throws
	{
		_ = NSApplication.shared
		let oldGate = TranscriptPreparationTestGate(heldBody: "old")
		let newGate = TranscriptPreparationTestGate(heldBody: "new")
		defer
		{
			oldGate.release()
			newGate.release()
		}
		let coordinator = TranscriptPreparationCoordinator(prepareContent:
			{
				key in
				if key.body == "old"
				{
					return try await oldGate.prepare(key)
				}
				return try await newGate.prepare(key)
			})
		let old = ConversationEntry(
			id: "old",
			kind: .agent,
			title: "Codex",
			body: "old"
		)
		let new = ConversationEntry(
			id: "new",
			kind: .agent,
			title: "Codex",
			body: "new"
		)
		var published: [String: PreparedConversationContent] = [:]
		coordinator.prepare(
			[old],
			keys: [.init(
				body: "old",
				markdown: true
			)]
		)
		{
			published = $0
		}
		try #require(await oldGate.waitUntilStarted())
		var waits = 0
		await coordinator.waitForRendering
		{
			waits += 1
			if waits == 1
			{
				coordinator
					.prepare(
						[new],
						keys: [.init(
							body: "new",
							markdown: true
						)]
					)
					{
						published = $0
					}
				oldGate.release()
			}
			else
			{
				newGate.release()
			}
		}
		newGate.release()
		#expect(published[new.id]?.attributedString.string == "new")
		#expect(published[old.id] == nil)
	}

	@Test
	func themeChangeRepreparesAnOtherwiseIdenticalTranscriptEntry() async throws
	{
		_ = NSApplication.shared
		let theme = ColorPreferences().configuration
		let old = theme.dark
		let changed = ColorThemeConfiguration(
			light: theme.light,
			dark: ColorThemeProfile(
				background: old.background ^ 1,
				foreground: old.foreground,
				accent: old.accent,
				contrast: old.contrast,
				diffAdded: old.diffAdded,
				diffRemoved: old.diffRemoved,
				skill: old.skill,
				namedAccent: old.namedAccent,
				colorizeMessages: old.colorizeMessages,
				presetID: old.presetID,
				codeThemeID: old.codeThemeID,
				opaqueWindows: old.opaqueWindows,
				hasCustomFonts: old.hasCustomFonts
			),
			mode: theme.mode
		)
		let entry = ConversationEntry(
			id: "turn:reply",
			kind: .agent,
			title: "Codex",
			body: "Hello"
		)
		let coordinator = TranscriptPreparationCoordinator()
		var published: [String: PreparedConversationContent] = [:]
		func prepare(_ configuration: ColorThemeConfiguration) async
		{
			let key = TranscriptPreparationCoordinator.ContentKey(
				body: entry.body,
				markdown: true,
				colorTheme: configuration
			)
			coordinator.prepare(
				[entry],
				keys: [key]
			)
			{
				published = $0
			}
			await coordinator.waitForRendering()
		}
		await prepare(theme)
		let first = try #require(published[entry.id])
		await prepare(theme)
		#expect(published[entry.id] === first)
		#expect(coordinator.contentPreparationRequestCount == 1)
		await prepare(changed)
		let updated = try #require(published[entry.id])
		#expect(updated !== first)
		#expect(updated.attributedString.string == first.attributedString.string)
		#expect(coordinator.contentPreparationRequestCount == 2)
	}

	@Test
	func deferredMathPreparationUpgradesTheCachedSourceWithoutReplacingItsMeaning() async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		let body = #"A formula: \(x^2 + y^2 = z^2\)."#
		let source = try await cache.content(
			body: body,
			markdown: true
		)
		#expect(source.hasUnpreparedRichBlocks)
		#expect(source.estimatedRichImageBytes == 0)
		let rendered = try await cache.content(
			body: body,
			markdown: true,
			prepareRichBlocks: true
		)
		#expect(!rendered.hasUnpreparedRichBlocks)
		#expect(rendered.estimatedRichImageBytes > 0)
		#expect(rendered.attributedString.string == source.attributedString.string)
		#expect(try await cache.content(
			body: body,
			markdown: true
		) === rendered)
	}

	@Test(arguments: [false, true])
	func richImageCostsEvictCachedMessagesBeforeTheEntryLimit(inlineMath: Bool) async throws
	{
		_ = NSApplication.shared
		let cache = ConversationContentCache()
		func source(index: Int) -> String
		{
			if inlineMath
			{
				let latex = #"\frac{"# + String(
					repeating: "x+",
					count: 24
				) + "\(index + 1)}{"
					+ String(
						repeating: "y+",
						count: 24
					) + "1}"
				return Array(
					repeating: #"\("# + latex + #"\)"#,
					count: 32
				)
				.joined(separator: " ") + "\n\nMessage \(index)"
			}
			let diagram = "```mermaid\nflowchart LR\n"
				+ "A[Independent message \(index)] --> B[Cache pressure]\n```"
			return Array(
				repeating: diagram,
				count: 8
			).joined(separator: "\n\n")
		}
		let firstSource = inlineMath ? source(index: -1)
			: "```mermaid\nflowchart LR\nA[First cached source] --> B[Result]\n```"
		let first = try await cache.content(
			body: firstSource,
			markdown: true,
			prepareRichBlocks: true
		)
		try #require(first.estimatedRichImageBytes > 0)
		#expect(try await cache.content(
			body: firstSource,
			markdown: true,
			prepareRichBlocks: true
		) === first)
		let capacity = 6 * 1024 * 1024
		var aggregateCost = firstSource.utf8.count + first.estimatedRichImageBytes
		var sourceBytes = firstSource.utf8.count
		var latestSource = firstSource
		var latest = first
		for index in 0 ..< 32
		{
			latestSource = source(index: index)
			latest = try await cache.content(
				body: latestSource,
				markdown: true,
				prepareRichBlocks: true
			)
			try #require(latest.estimatedRichImageBytes > 0)
			aggregateCost += latestSource.utf8.count + latest.estimatedRichImageBytes
			sourceBytes += latestSource.utf8.count
			if aggregateCost > capacity
			{
				break
			}
		}
		try #require(aggregateCost > capacity)
		#expect(sourceBytes < capacity)
		#expect(try await cache.content(
			body: latestSource,
			markdown: true
		) === latest)
		let reloadedFirst = try await cache.content(
			body: firstSource,
			markdown: true,
			prepareRichBlocks: true
		)
		#expect(reloadedFirst !== first)
		#expect(reloadedFirst.codeBlocks == first.codeBlocks)
		#expect(reloadedFirst.attributedString.string == first.attributedString.string)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
