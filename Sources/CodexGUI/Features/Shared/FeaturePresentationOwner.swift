import Foundation

/// Captures runtime ownership even when different stores show the same checkout and conversation.
/// The optional identity supports older callers while snapshot scope remains authoritative.
struct FeaturePresentationOwner: Equatable
{
	let storeIdentity: String?
	let runtimeOwner: WorkspaceLifecycleOwnerReference?
	let selectionEpoch: Int
	let projectPath: String?
	let selectedThreadID: String?

	init(
		_ snapshot: ConversationSnapshot,
		storeIdentity: String? = nil
	)
	{
		self.storeIdentity = storeIdentity
		runtimeOwner = snapshot.workspaceOwner
		selectionEpoch = snapshot.workspaceSelectionEpoch
		projectPath = snapshot.projectPath
		selectedThreadID = snapshot.selectedThreadID
	}

	private var components: [String?]
	{
		let lifecycleIdentity: String? = runtimeOwner.map
		{
			reference in
			switch reference.owner
			{
			case .source(let session): return "source:\(session.uuidString)"
			case .managed(
				let workspace,
				let session
			):
				return "managed:\(workspace.uuidString):\(session.uuidString)"
			}
		}
		return [
			lifecycleIdentity,
			runtimeOwner?.workspace.sessionID.uuidString,
			runtimeOwner?.workspace.canonicalCheckoutPath,
			String(selectionEpoch),
			storeIdentity,
			projectPath,
		]
	}

	var projectIdentity: String
	{
		Self.encode(components)
	}

	var transcriptIdentity: String
	{
		Self.encode(components + [selectedThreadID])
	}

	func draftIdentity(lifetime: Int) -> String
	{
		Self.encode(components + [selectedThreadID, String(lifetime)])
	}

	private static func encode(_ components: [String?]) -> String
	{
		// Length-prefixed components distinguish separator characters and nil from empty strings.
		components.map
		{
			value in value.map
			{
				"\($0.utf8.count):\($0)"
			} ?? "-"
		}.joined(separator: "|")
	}

}
