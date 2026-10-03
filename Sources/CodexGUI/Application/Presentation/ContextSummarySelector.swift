import Foundation

/// One atomic projection of both canonical providers; neither owns a second summary inventory.
@MainActor
enum ContextSummarySelector
{
	static func sections(
		model: WorkspaceModel,
		chatID: String?,
		changes: SummarySection<SummaryChangeTotals> = .unavailable("Totals unavailable")
	) -> ContextSummarySections
	{
		var sections = ContextSummarySections()
		guard model.identity.canonicalCheckoutPath != nil, !model.lifecycle.isShutdown
		else
		{
			sections.changes = .unavailable("Workspace unavailable")
			sections.sources = .unavailable("Workspace unavailable")
			sections.availableDestinations = []
			return sections
		}
		sections.changes = changes
		guard chatID != nil
		else
		{
			return sections
		}
		// Workspace Git totals require an owner-scoped canonical comparison provider.
		return sections
	}
}
