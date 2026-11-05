import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct ComposerCompleteControlTests
{
	@Test func freshPermissionTitleFitsBeforeTypographyRefresh() throws
	{
		_ = NSApplication.shared
		let button = ComposerPermissionButton(frame: .zero)
		button.frame.size = button.intrinsicContentSize
		let cell = try #require(button.cell)
		let titleRect = cell.titleRect(forBounds: button.bounds)
		let titleBounds = button.attributedTitle.boundingRect(
			with: NSSize(
				width: titleRect.width,
				height: 1000
			),
			options: [.usesLineFragmentOrigin, .usesFontLeading]
		)
		#expect(titleBounds.height <= button.bounds.height)
		#expect(titleRect.width >= button.attributedTitle.size().width)
	}

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
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			button.appearance = NSAppearance(named: appearance)
			#expect(matchesColor(
				button.layerBackgroundColor,
				AppKitColorTokens.mutedText,
				for: button
			))
		}
		button.isEnabled = true
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			button.appearance = NSAppearance(named: appearance)
			#expect(matchesColor(
				button.layerBackgroundColor,
				AppKitColorTokens.composerSend,
				for: button
			))
		}
		#expect(button.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
		#expect(button.keyEquivalent == "\r")
		#expect(button.keyEquivalentModifierMask == [.command])
	}

	@Test func configuredPermissionThenPresetRestoresArtworkTintAndAction() throws
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
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			button.appearance = NSAppearance(named: appearance)
			#expect(matchesColor(
				button.contentTintColor,
				AppKitColorTokens.composerSecondaryText,
				for: button
			))
		}
		#expect(button.toolTip == "Configured permissions: Read-only files")
		button.render(mode: .fullAccess)
		let paragraph = try #require(button.attributedTitle.attribute(
			.paragraphStyle,
			at: 0,
			effectiveRange: nil
		) as? NSParagraphStyle)
		#expect(paragraph.minimumLineHeight >= 18)
		#expect(button.image === ComposerFooterIcons.fullAccess)
		#expect(matchesColor(
			button.contentTintColor,
			ApprovalPopoverStyle.fullAccess,
			for: button
		))
		button.render(mode: .approveForMe)
		#expect(button.title == ApprovalMode.approveForMe.title)
		#expect(button.image !== ComposerFooterIcons.fullAccess)
		for appearance in [NSAppearance.Name.aqua, .darkAqua]
		{
			button.appearance = NSAppearance(named: appearance)
			#expect(matchesColor(
				button.contentTintColor,
				AppKitColorTokens.composerSecondaryText,
				for: button
			))
		}
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
