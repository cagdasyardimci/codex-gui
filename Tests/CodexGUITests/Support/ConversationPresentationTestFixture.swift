import Foundation
import Testing

@testable import CodexGUI

@MainActor
enum ConversationPresentationTestFixture
{
	static func presentationOwner(sessionID: UUID) -> WorkspaceLifecycleOwnerReference
	{
		WorkspaceLifecycleOwnerReference(
			owner: .source(sessionID: sessionID),
			workspace: WorkspaceIdentity(
				sessionID: sessionID,
				canonicalCheckoutPath: "/tmp/replay"
			)
		)
	}

}
