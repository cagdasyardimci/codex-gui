import AppKit

typealias GitRichPreviewKind = RichFilePreviewKind

/// Git owns snapshot identity and the comparison-specific loading failure copy.
@MainActor
final class GitRichPreviewView: RichFilePreviewView
{
	init(
		kind: GitRichPreviewKind,
		loadContent: @escaping @Sendable () async throws -> Data
	)
	{
		super.init(
			kind: kind,
			loadingFailureMessage: "Rich preview unavailable. Refresh the comparison and retry.",
			loadContent: loadContent
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
