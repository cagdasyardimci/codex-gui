import Foundation
import Testing

@testable import CodexGUI

struct GitComparisonSnapshotTests
{
	@Test func copyPayloadPreservesExactBytesAndRejectsBinary() throws
	{
		let patch = Data("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n".utf8)
		let snapshot = GitComparisonSnapshot(
			request: request(
				root: "/tmp/fixture",
				scope: .unstaged
			),
			id: "fixture",
			resolvedBase: "Index",
			resolvedTarget: "Working tree",
			patch: patch,
			files: GitComparisonPatchParser.files(in: patch)
		)
		let command = try #require(snapshot.copyCommand)
		#expect(command == "printf '%s' '" + patch.base64EncodedString()
			+ "' | base64 -D | git -C '/tmp/fixture' apply")
		let binary = Data("diff --git a/x b/x\nBinary files a/x and b/x differ\n".utf8)
		let unsupported = GitComparisonSnapshot(
			request: snapshot.request,
			id: "binary",
			resolvedBase: "Index",
			resolvedTarget: "Working tree",
			patch: binary,
			files: GitComparisonPatchParser.files(in: binary)
		)
		#expect(unsupported.copyCommand == nil)
	}

	private func request(
		root: String,
		scope: GitComparisonScope
	) -> GitComparisonRequest
	{
		let snapshot = ConversationSnapshot(
			projectPath: root,
			threads: [],
			selectedThreadID: "fixture-thread",
			entries: [],
			canLoadEarlierTurns: false,
			changedFiles: [],
			diff: "",
			draft: "",
			canSend: false,
			accountDescription: "",
			backendDescription: "",
			executionState: .ready,
			statusMessage: nil,
			models: [],
			selectedModelID: nil,
			selectedEffort: nil,
			pendingInteractions: [],
			recentProjects: []
		)
		return GitComparisonRequest(
			owner: FeaturePresentationOwner(snapshot),
			repositoryRoot: root,
			scope: scope,
			generation: 1
		)
	}
}
