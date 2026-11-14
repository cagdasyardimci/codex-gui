import AppKit

extension MainWindowController
{
	func showProjectCreation(target: WorkspaceIntentTarget)
	{
		guard let window, window.attachedSheet == nil, target.accepts(.newChat)
		else
		{
			return
		}
		let form = ProjectCreationViewController()
		form.loadViewIfNeeded()
		let panel = DesktopConfirmationPanel(
			contentRect: .zero,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		panel.isReleasedWhenClosed = false
		panel.isOpaque = false
		panel.backgroundColor = .clear
		panel.hasShadow = true
		panel.title = "Create project"
		panel.contentViewController = form
		form.view.layoutSubtreeIfNeeded()
		panel.setContentSize(form.view.fittingSize)
		panel.initialFirstResponder = form.nameField.input
		panel.defaultButtonCell = form.createButton.cell as? NSButtonCell
		form.onDecision =
		{
			[weak panel] in panel?.finishDecision($0)
		}
		panel.beginSheet(in: window)
		{
			[panel, form] response in
			panel.orderOut(nil)
			guard response == .OK, target.accepts(.newChat),
					let folder = form.folder
			else
			{
				return
			}
			target.dispatch(.renameProject(
				folder,
				form.projectName
			))
			target.dispatch(.openProject(folder))
		}
		(form.view as? DesktopDialogShell)?.resize(window: panel)
	}
}
