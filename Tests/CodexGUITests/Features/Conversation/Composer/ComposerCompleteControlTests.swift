import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct ComposerCompleteControlTests
{
	@Test(arguments: [ComposerSubmissionButton.Role.send, .steer])
	func disabledSubmissionRestoresItsSurfaceAndNativeAction(role: ComposerSubmissionButton.Role)
	{
		_ = NSApplication.shared
		let button = ComposerSubmissionButton(role: role)
		let receiver = ActionReceiver()
		button.target = receiver
		button.action = #selector(ActionReceiver.invoke)
		button.isEnabled = false
		#expect(!button.dispatchConfiguredAction())
		#expect(receiver.calls == 0)
		#expect(button.layerBackgroundColor == .tertiaryLabelColor)
		button.isEnabled = true
		#expect(button.layerBackgroundColor == AppKitColorTokens.composerSend)
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
		#expect(button.keyEquivalent == "\r")
		#expect(button.keyEquivalentModifierMask == (role == .send ? [.command] : [
			.command,
			.shift
		]))
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
		#expect(button.contentTintColor == AppKitColorTokens.composerSecondaryText)
		#expect(button.toolTip == "Configured permissions: Read-only files")
		button.render(mode: .fullAccess)
		#expect(button.image === ComposerFooterIcons.fullAccess)
		#expect(button.contentTintColor == ApprovalPopoverStyle.fullAccess)
		button.render(mode: .approveForMe)
		#expect(button.title == ApprovalMode.approveForMe.title)
		#expect(button.image !== ComposerFooterIcons.fullAccess)
		#expect(button.contentTintColor == AppKitColorTokens.composerSecondaryText)
		#expect(button
			.accessibilityLabel() == "Approval policy: \(ApprovalMode.approveForMe.title)")
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
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
