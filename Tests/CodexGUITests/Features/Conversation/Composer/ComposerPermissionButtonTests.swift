import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ComposerPermissionButtonTests
{
	@Test func permissionLabelsKeepNaturalWidthAndReferenceContentInsets() throws
	{
		_ = NSApplication.shared
		let controller = ConversationViewController()
		_ = controller.view
		let button = controller.approvalPolicyButton
		let cell = try #require(button.cell as? ComposerPermissionButtonCell)
		var widths: [CGFloat] = []
		for title in ["Full access", "Ask for approval", "A longer approval policy label"]
		{
			button.title = title
			let size = button.intrinsicContentSize
			widths.append(size.width)
			let bounds = NSRect(
				x: 0,
				y: 0,
				width: size.width,
				height: 28
			)
			let icon = cell.imageRect(forBounds: bounds)
			let text = cell.titleRect(forBounds: bounds)
			#expect(icon == NSRect(
				x: 7,
				y: 6,
				width: 16,
				height: 16
			))
			#expect(text.minX - icon.maxX == 4)
			#expect(text.maxX <= bounds.maxX - 7)
			let naturalWidth = (title as NSString).size(withAttributes: [
				.font: try #require(button.font),
			]).width
			#expect(abs(text.width - naturalWidth) < 0.01)
			if title == "Full access"
			{
				#expect(abs(size.width - 101.05) < 0.01)
				if let output = ProcessInfo.processInfo.environment["CODEX_GUI_PERMISSION_CAPTURE"]
				{
					button.frame = bounds
					button.image = ComposerFooterIcons.fullAccess
					button.contentTintColor = ApprovalPopoverStyle.fullAccess
					button.attributedTitle = NSAttributedString(
						string: title,
						attributes: [
							.font: try #require(button.font),
							.foregroundColor: ApprovalPopoverStyle.fullAccess,
						]
					)
					try AppTestPNGWriter.write(
						button,
						to: URL(fileURLWithPath: output)
					)
				}
			}
		}
		#expect(widths[0] < widths[1])
		#expect(widths[1] < widths[2])
	}
}
