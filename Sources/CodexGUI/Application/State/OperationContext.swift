import Foundation

/// Captured at the effect boundary after CheckoutIdentity validates the filesystem target.
/// The session distinguishes two stores using the same canonical checkout.
struct WorkspaceIdentity: Equatable, Hashable, Sendable
{
	let sessionID: UUID
	/// Nil identifies a source session before a checkout is selected; it is never a wildcard.
	let canonicalCheckoutPath: String?
}

/// A request exists before the backend assigns a thread or turn to a new submission.
struct OperationContext: Equatable, Sendable
{
	let workspace: WorkspaceIdentity
	let generation: Int
	let requestID: UUID
	var threadID: String? = nil
	var turnID: String? = nil
	var itemID: String? = nil

	func belongsTo(
		workspace: WorkspaceIdentity,
		generation: Int
	) -> Bool
	{
		self.workspace == workspace && self.generation == generation
	}

	/// Compare the captured request independently of backend IDs bound after acknowledgement.
	func isSameRequest(as other: OperationContext) -> Bool
	{
		workspace == other.workspace && generation == other.generation
			&& requestID == other.requestID
	}
}

/// Payload failures are values; runtime Error instances stay at the effect boundary.
struct OperationFailure: Equatable, Sendable
{
	let message: String
	let outcomeIsUncertain: Bool
}

enum OperationResult<Value>
{
	case succeeded(Value)
	case failed(OperationFailure)
}

/// Captures the cursor and command evidence for one scoped history page.
struct HistoryLoadOperation
{
	let context: OperationContext
	let pageScope: HistoryPageScope
	/// A late page may not overwrite command evidence observed after this revision.
	let commandRevision: Int
	var scope: HistoryPageScope
	{
		pageScope
	}
}

struct InteractionResponseOperation
{
	let context: OperationContext
	let interactionID: String
	let response: InteractionResponse
}

struct SteeringOperation
{
	let context: OperationContext
	let submission: ComposerSubmission
}

struct InterruptionOperation
{
	let context: OperationContext
}

struct ReconciliationOperation: Equatable
{
	let context: OperationContext
	let commandRevision: Int
	var contentOnly = false
}

enum ConversationReadPurpose: Hashable
{
	case selection, search, recovery, completion
}

struct ConversationReadOperation
{
	let context: OperationContext
	let commandRevision: Int
	let purpose: ConversationReadPurpose
	var contentRevision = 0
	var key: ConversationReadKey
	{
		ConversationReadKey(
			purpose: purpose,
			threadID: context.threadID ?? ""
		)
	}
}

struct ConversationReadKey: Hashable
{
	let purpose: ConversationReadPurpose
	let threadID: String
}

struct ConversationListOperation
{
	let context: OperationContext
	let archived: Bool
	var boundThreadID: String? = nil
	var allProjects = false
}

struct ContextLoadOperation
{
	let context: OperationContext
	let revision: Int
}

struct ContextSaveOperation
{
	let context: OperationContext
	let revision: Int
	let value: ProjectContext
}

struct SkillsRefreshOperation
{
	let context: OperationContext
	let attempt: Int
}

enum NavigationHistoryRead
{
	case history(ConversationReadOperation)
	case page(HistoryLoadOperation)
	case turn(ConversationTurnReadOperation)

	var context: OperationContext
	{
		switch self
		{
		case .history(let operation): return operation.context
		case .page(let operation): return operation.context
		case .turn(let operation): return operation.context
		}
	}
}

struct NavigationSearchOperation
{
	let context: OperationContext
	var read: NavigationHistoryRead?
}

struct MessageSearchOperation: Equatable, Sendable
{
	let context: OperationContext
	let query: String
	let historyRevision: Int
}

struct ConversationJumpOperation
{
	let context: OperationContext
	let turnID: String
	let itemID: String?
	var pagesLoaded = 0
	var pendingRead: NavigationHistoryRead?
	var resolvedItemID: String?
}
