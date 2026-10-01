import Foundation

extension WorkspaceSelectors
{
	var composerCommandAvailable: Bool
	{
		guard !model.lifecycle.isShutdown, model.lifecycle.cleanupReservation == nil,
				model.lifecycle.quitReservation == nil
		else
		{
			return false
		}
		switch SlashCommandParser.parse(draft)
		{
		case .text: return false
		case .command(let invocation):
			if invocation.id == .plan && !invocation.trimmedArguments.isEmpty
			{
				return WorkspaceEligibility(model: model).canSend
			}
			return ComposerCommandReducer.unavailableReason(
				invocation.id,
				model: model
			) == nil
		case .error: return true
		}
	}
}
