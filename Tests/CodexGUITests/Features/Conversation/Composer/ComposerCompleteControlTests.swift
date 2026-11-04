import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct ComposerCompleteControlTests
{
	@Test
	func disabledSubmissionRestoresItsSurfaceAndNativeAction()
	{
		_ = NSApplication.shared
		let button = ComposerSubmissionButton(role: .send)
		let receiver = ActionReceiver()
		button.target = receiver
		button.action = #selector(ActionReceiver.invoke)
		button.isEnabled = false
		#expect(!button.dispatchConfiguredAction())
		#expect(receiver.calls == 0)
		#expect(button.layerBackgroundColor == .tertiaryLabelColor)
		button.isEnabled = true
		#expect(matchesColor(
			button.layerBackgroundColor,
			AppKitColorTokens.composerSend,
			for: button
		))
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
		#expect(button.keyEquivalent == "\r")
		#expect(button.keyEquivalentModifierMask == [.command])
	}

	@Test func configuredPermissionThenPresetRestoresArtworkTintAndAction()
	{
		_ = NSApplication.shared
		let button = ComposerPermissionButton(frame: .zero)
		let receiver = ActionReceiver()
		button.target = receiver
		button.action = #selector(ActionReceiver.invoke)
		button.render(
			mode: .fullAccess,
			configuredDescription: "Read-only files",
			configuredFullAccess: false
		)
		#expect(button.title == "Configured permissions")
		#expect(matchesColor(
			button.contentTintColor,
			AppKitColorTokens.composerSecondaryText,
			for: button
		))
		#expect(button.toolTip == "Configured permissions: Read-only files")
		button.render(mode: .fullAccess)
		#expect(button.image === ComposerFooterIcons.fullAccess)
		#expect(button.contentTintColor == ApprovalPopoverStyle.fullAccess)
		button.render(mode: .approveForMe)
		#expect(button.title == ApprovalMode.approveForMe.title)
		#expect(button.image !== ComposerFooterIcons.fullAccess)
		#expect(matchesColor(
			button.contentTintColor,
			AppKitColorTokens.composerSecondaryText,
			for: button
		))
		#expect(button
			.accessibilityLabel() == "Approval policy: \(ApprovalMode.approveForMe.title)")
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
	}

	private func matchesColor(
		_ actual: NSColor?,
		_ expected: NSColor,
		for view: NSView
	) -> Bool
	{
		guard let actual
		else
		{
			return false
		}
		return AppKitColorResolution.resolvedCGColor(
			actual,
			for: view
		).components
			== AppKitColorResolution.resolvedCGColor(
				expected,
				for: view
			).components
	}

	@MainActor
	private final class ActionReceiver: NSObject
	{
		var calls = 0
		@objc func invoke()
		{
			calls += 1
		}
	}
}
