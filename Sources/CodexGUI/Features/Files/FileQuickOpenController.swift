import AppKit

@MainActor
final class FileQuickOpenController
{
	var onSearch: ((String) -> Void)?
	var onChoose: ((FileLocation) -> Void)?
	var onDismiss: (() -> Void)?
	var onCancelSearch: (() -> Void)?

	private lazy var panel = FileSearchPanel(mode: .filename)

	init()
	{
		panel.onQuery =
		{
			[weak self] query, _ in self?.onSearch?(query)
		}
		panel.onChooseFilename =
		{
			[weak self] location in self?.onChoose?(location)
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
