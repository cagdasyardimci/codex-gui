import Foundation

/// Providers project their canonical records; unavailable is distinct from a known empty value.
enum SummarySection<Value: Equatable>: Equatable
{
	case unavailable(String)
	case loading(previous: Value?)
	case available(Value)
	case failed(
		String,
		previous: Value?
	)

	var value: Value?
	{
		switch self
		{
		case .available(let value): value
		case .loading(let previous), .failed(
			_,
			let previous
		): previous
		case .unavailable: nil
		}
	}

	var message: String?
	{
		switch self
		{
		case .unavailable(let reason), .failed(
			let reason,
			_
		): reason
		case .loading: "Loading…"
		case .available: nil
		}
	}
}

/// Source identity must be supplied by the canonical Sources inventory, never a display name.
struct SummarySourceReference: Equatable, Identifiable
{
	enum Kind: Equatable
	{
		case attachment, tool, web, folder
	}
	let id: String
	let label: String
	let kind: Kind
	var thumbnailPath: String? = nil
	/// Nil means preview only; the provider has not established a resource destination.
	var detailRecordID: String? = nil
}

/// Stable backend identity shared by delegated-work projections and historical activity.
struct DelegatedAgentIdentity: Hashable
{
	let parentThreadID: String
	let agentThreadID: String
	/// Distinguishes separate executions by the same agent.
	var runID: String? = nil
}

struct SummaryAgentProjection: Equatable
{
	let identities: [DelegatedAgentIdentity]
	let completedCount: Int
	let runningCount: Int
	let aggregationDescription: String
}

struct SummaryChangeTotals: Equatable
{
	let additions: Int
	let deletions: Int
}

/// Immutable projections only. Feature reducers own records, revisions and reconciliation.
struct ContextSummarySections: Equatable
{
	var changesContext: String? = nil
	var changes: SummarySection<SummaryChangeTotals> = .unavailable("Totals unavailable")
	var agents: SummarySection<SummaryAgentProjection> = .unavailable("Subagents unavailable")
	var sources: SummarySection<[SummarySourceReference]> = .unavailable("Sources unavailable")
	var availableDestinations: Set<ContextPanelDestination> = [.changes]
}

/// An adapter result is scoped and ordered even when the card is hidden.
struct ContextSummaryUpdate: Equatable
{
	let owner: FeaturePresentationOwner
	let revision: Int
	let sections: ContextSummarySections
}
