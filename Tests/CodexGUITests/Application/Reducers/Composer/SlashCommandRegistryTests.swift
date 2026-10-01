import Testing

@testable import CodexGUI

@Suite
struct SlashCommandRegistryTests
{
	@Test func commandCatalogIsCompleteUniqueAndDoesNotAdvertiseUnsupportedCommands()
	{
		let ids = SlashCommandRegistry.commands.map(\.id)
		#expect(Set(ids) == Set(SlashCommandID.allCases))
		#expect(Set(ids).count == ids.count)
		let names = SlashCommandRegistry.commands.flatMap
		{
			[$0.name] + $0.aliases
		}
		#expect(Set(names).count == names.count)
		#expect(!names.contains("personality"))
		#expect(!names.contains("init"))
		#expect(!names.contains("goals"))
		#expect(!names.contains("queue"))
		#expect(!names.contains("plugins"))
		#expect(SlashCommandRegistry.commands.allSatisfy
		{
			!$0.description.isEmpty && $0.usage.hasPrefix("/\($0.name)")
		})
	}

	@Test func completionUsesCanonicalMetadataInCatalogOrder()
	{
		#expect(SlashCommandRegistry.matching(prefix: "") == SlashCommandRegistry.commands)
		#expect(SlashCommandRegistry.matching(prefix: "RE").map(\.id) == [
			.resume,
			.rename,
			.review,
			.reasoning,
		])
		#expect(SlashCommandRegistry.matching(prefix: "does-not-exist").isEmpty)
		#expect(SlashCommandRegistry.descriptor(for: "PLAN")?.id == .plan)
		#expect(SlashCommandRegistry.descriptor(for: .plan).acceptsInlinePrompt)
		#expect(SlashCommandRegistry.descriptor(for: .rename).acceptsArguments)
		#expect(!SlashCommandRegistry.descriptor(for: .copy).acceptsArguments)
	}
}
