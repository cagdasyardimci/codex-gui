import AppKit
import Testing

@testable import CodexGUI

@MainActor
struct DesktopNativeButtonTests
{
	@Test(arguments: [DesktopStyledButton.Presentation.nativeDefault,
						.nativeInline,
						.nativeProminent,
						.nativeIcon])
	func nativePresetsRetainPreviousCellGeometry(_ presentation: DesktopStyledButton.Presentation)
	{
		_ = NSApplication.shared
		let expected = NSButton(
			title: "Open project",
			target: nil,
			action: nil
		)
		if presentation != .nativeDefault
		{
			AppKitControlStyling.styleButton(
				expected,
				icon: .folder,
				prominent: presentation == .nativeProminent
			)
			if presentation == .nativeIcon
			{
				expected.imagePosition = .imageOnly
			}
		}
		let actual = DesktopStyledButton(
			title: "Open project",
			presentation: presentation
		)
		if presentation != .nativeDefault
		{
			actual.symbol = .folder
		}
		#expect(actual.intrinsicContentSize == expected.intrinsicContentSize)
		#expect(actual.alignmentRectInsets.top == expected.alignmentRectInsets.top)
		#expect(actual.alignmentRectInsets.bottom == expected.alignmentRectInsets.bottom)
		#expect(actual.font == expected.font)
		#expect(actual.bezelStyle == expected.bezelStyle)
		#expect(actual.isBordered == expected.isBordered)
		#expect(actual.controlSize == expected.controlSize)
		#expect(actual.imagePosition == expected.imagePosition)
		let bounds = NSRect(
			x: 0,
			y: 0,
			width: 180,
			height: 30
		)
		#expect((actual.cell as? NSButtonCell)?.titleRect(forBounds: bounds)
			== (expected.cell as? NSButtonCell)?.titleRect(forBounds: bounds))
	}


	@Test func defaultNativeReconfigurationRetainsConfiguredCellAndAction()
	{
		_ = NSApplication.shared
		var calls = 0
		let button = DesktopActionButton(
			title: "Save",
			presentation: .nativeDefault
		)
		{
			calls += 1
		}
		let configuredCell = button.cell
		button.setButtonType(.toggle)
		button.state = .on
		button.keyEquivalent = "s"
		button.keyEquivalentModifierMask = [.command]
		button.size = .regular
		button.presentation = .nativeDefault
		#expect(button.cell === configuredCell)
		#expect(button.state == .on)
		#expect(button.keyEquivalent == "s")
		#expect(button.keyEquivalentModifierMask == [.command])
		#expect(button.dispatchConfiguredAction())
		#expect(calls == 1)
		button.presentation = .primary
		#expect(button.dispatchConfiguredAction())
		button.presentation = .nativeDefault
		#expect(button.state == .on)
		#expect(button.keyEquivalent == "s")
		#expect(button.dispatchConfiguredAction())
		#expect(calls == 3)
	}

}
