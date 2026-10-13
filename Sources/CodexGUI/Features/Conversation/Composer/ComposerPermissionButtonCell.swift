import AppKit

final class ComposerPermissionButtonCell: NSButtonCell
{
	private let contentLayout: PermissionControlLayout

	init(
		textCell: String,
		metrics: LayoutTokens.Permission = LayoutTokens.permission
	)
	{
		precondition(
			metrics.isValid,
			"Invalid permission control metrics"
		)
		contentLayout = PermissionControlLayout(metrics: metrics)
		super.init(textCell: textCell)
	}

	required init(coder: NSCoder)
	{
		contentLayout = PermissionControlLayout()
		super.init(coder: coder)
	}

	static let titleLeadingInset = LayoutTokens.permission.titleLeadingInset
	static let titleTrailingInset = LayoutTokens.permission.trailingInset
	static let titleHorizontalInset = LayoutTokens.permission.titleHorizontalInset
	func requestedWidth(titleWidth: CGFloat) -> CGFloat
	{
		contentLayout.requestedWidth(titleWidth: titleWidth)
	}

	override func imageRect(forBounds rect: NSRect) -> NSRect
	{
		contentLayout.imageRect(in: rect)
	}

	override func titleRect(forBounds rect: NSRect) -> NSRect
	{
		contentLayout.titleRect(
			in: rect,
			nativeTitleRect: super.titleRect(forBounds: rect)
		)
	}
}
