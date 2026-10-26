import AppKit

/// Terminal copy semantics use the complete shared control's terminal presentation.
@MainActor
final class ConversationTerminalCopyButton: DesktopCopyButton
{
	init(frame: NSRect = .zero)
	{
		super.init(
			presentation: .terminal,
			frame: frame
		)
	}

	required init?(coder: NSCoder)
	{
		nil
	}
}
