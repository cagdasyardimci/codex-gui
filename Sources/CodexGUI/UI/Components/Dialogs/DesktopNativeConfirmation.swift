import AppKit

/// Complete native confirmation with semantic default action and one response owner.
@MainActor
final class DesktopNativeConfirmation
{
	enum DefaultAction
	{
		case cancel, confirm
	}

	enum Emphasis
	{
		case standard, warning
	}

	let alert: NSAlert
	private let confirmedResponse: NSApplication.ModalResponse
	private var hasPresented = false
	private var hasFinished = false

	init(
		title: String,
		message: String,
		confirmTitle: String,
		cancelTitle: String = "Cancel",
		defaultAction: DefaultAction = .cancel,
		emphasis: Emphasis = .standard
	)
	{
		alert = NSAlert()
		alert.messageText = title
		alert.informativeText = message
		if emphasis == .warning
		{
			alert.alertStyle = .warning
		}
		switch defaultAction
		{
		case .cancel:
			alert.addButton(withTitle: cancelTitle)
			alert.addButton(withTitle: confirmTitle)
			confirmedResponse = .alertSecondButtonReturn
		case .confirm:
			alert.addButton(withTitle: confirmTitle)
			alert.addButton(withTitle: cancelTitle)
			confirmedResponse = .alertFirstButtonReturn
		}
	}

	func beginSheet(
		in window: NSWindow,
		completion: @escaping (Bool) -> Void
	)
	{
		guard !hasPresented
		else
		{
			return
		}
		hasPresented = true
		alert.beginSheetModal(for: window)
		{
			[self] response in
			if let decision = finish(response)
			{
				completion(decision)
			}
		}
	}

	func runModal() -> Bool
	{
		guard !hasPresented
		else
		{
			return false
		}
		hasPresented = true
		return finish(alert.runModal()) ?? false
	}

	private func finish(_ response: NSApplication.ModalResponse) -> Bool?
	{
		guard !hasFinished
		else
		{
			return nil
		}
		hasFinished = true
		return response == confirmedResponse
	}
}
