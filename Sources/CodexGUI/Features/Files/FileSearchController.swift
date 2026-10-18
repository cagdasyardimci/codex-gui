import AppKit

@MainActor
final class FileSearchController
{
	var onSearch: ((String, String?) -> Void)?
	var onChoose: ((FileViewerSearchResult) -> Void)?
	var onDismiss: (() -> Void)?
	var onCancelSearch: (() -> Void)?

	private lazy var panel = FileSearchPanel(mode: .content)

	init()
	{
		panel.onQuery =
		{
			[weak self] query, mask in self?.onSearch?(query, mask)
		}
		panel.onChooseContent =
		{
			[weak self] result in self?.onChoose?(result)
		}
		panel.onDismiss =
		{
			[weak self] in self?.onDismiss?()
		}
		panel.onCancelSearch =
		{
			[weak self] in self?.onCancelSearch?()
		}
	}

	func render(_ state: FileViewerState)
	{
		panel.render(state)
	}
	func present(in window: NSWindow)
	{
		panel.present(in: window)
	}
	func focusSearch()
	{
		panel.focusSearch()
	}
	func dismiss()
	{
		panel.dismiss()
	}
}
