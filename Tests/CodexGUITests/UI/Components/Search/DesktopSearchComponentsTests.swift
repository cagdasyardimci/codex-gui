import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopSearchComponentsTests
{

	@Test func attachmentResultPreservesNativeMetricsAndRoutesTheExactPath() throws
	{
		_ = NSApplication.shared
		let receiver = SearchAttachmentReceiver()
		let path = "Sources/folder with spaces=value.swift"
		let result = DesktopSearchResultButton.attachment(
			path: path,
			target: receiver,
			action: #selector(SearchAttachmentReceiver.choose(_:))
		)
		let native = NSButton(
			title: path,
			target: nil,
			action: nil
		)
		native.bezelStyle = .inline
		native.alignment = .left
		#expect(result.title == path)
		#expect(result.frame.size == native.frame.size)
		#expect(result.intrinsicContentSize == native.intrinsicContentSize)
		#expect(result.font == native.font)
		#expect(result.bezelStyle == native.bezelStyle)
		#expect(result.alignment == native.alignment)
		#expect(result.cell?.lineBreakMode == native.cell?.lineBreakMode)
		let bounds = NSRect(
			origin: .zero,
			size: native.intrinsicContentSize
		)
		#expect(result.cell?.titleRect(forBounds: bounds) == native.cell?
			.titleRect(forBounds: bounds))
		#expect(result.accessibilityLabel() == "Attach project file \(path)")
		#expect(result.dispatchConfiguredAction())
		#expect(receiver.chosenPath == path)
	}

}

@MainActor
private final class SearchAttachmentReceiver: NSObject
{
	var chosenPath: String?

	@objc func choose(_ sender: NSButton)
	{
		chosenPath = sender.identifier?.rawValue
	}
}
