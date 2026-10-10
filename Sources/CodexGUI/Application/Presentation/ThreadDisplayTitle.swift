import Foundation

/// Presentation fallbacks never alter the server's title, preview or conversation history.
extension ThreadSummary
{
	var displayTitle: String
	{
		if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		{
			return name.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		let request = UserMessagePresenter.previewRequest(in: preview ?? "")
		let title = ThreadTitleText.normalized(request)
		if !title.isEmpty
		{
			return title
		}
		let path = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
		return path.isEmpty ? "New chat" : path
	}
}
