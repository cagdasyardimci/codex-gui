import Foundation
import Testing

@testable import CodexGUI

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
