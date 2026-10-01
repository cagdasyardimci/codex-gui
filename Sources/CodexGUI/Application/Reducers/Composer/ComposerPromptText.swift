import Foundation

/// Submission and admission use the same command transformation without changing draft provenance.
enum ComposerPromptText
{
	static func submittedText(
		_ draft: String,
		collaborationMode: CollaborationMode?
	) -> String?
	{
		switch SlashCommandParser.parse(draft)
		{
		case .text(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines)
		case .command(let invocation):
			guard invocation.id == .plan, !invocation.trimmedArguments.isEmpty,
					collaborationMode?.mode == .plan
			else
			{
				return nil
			}
			return invocation.arguments
		case .error: return nil
		}
	}
}
