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

	@Test func submissionActionsPaintSquareBoundsInTheComposerRow()
	{
		_ = NSApplication.shared
		let actions = [
			ComposerSubmissionButton.Role.send,
			.resume,
			.stop,
			.startVoiceChat,
			.endVoiceChat
		]
		.map
		{
			ComposerSubmissionButton(role: $0)
		}
		let size = LayoutTokens.composer.controlHeight
		let host = NSView(frame: NSRect(
			x: 0,
			y: 0,
			width: 240,
			height: 48
		))
		let row = AppKitLayout.horizontalStack(actions)
		row.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(row)
		NSLayoutConstraint.activate([
			row.centerXAnchor.constraint(equalTo: host.centerXAnchor),
			row.centerYAnchor.constraint(equalTo: host.centerYAnchor),
		])
		for action in actions
		{
			for button in actions
			{
				button.isHidden = button !== action
			}
			host.layoutSubtreeIfNeeded()
			#expect(action.bounds.size == NSSize(
				width: size,
				height: size
			))
			if action.role != .stop
			{
				#expect(action.layer?.cornerRadius == size / 2)
			}
		}
	}

	@Test func composerMicrophoneShowsARedCircleOnlyWhileMuted() throws
	{
		_ = NSApplication.shared
		let controls = VoiceChatControls()
		controls.frame.size = NSSize(
			width: 94,
			height: 28
		)
		controls.layoutSubtreeIfNeeded()
		let microphone = controls.microphone
		let unmutedFrame = microphone.frame
		controls.render(
			microphoneMuted: true,
			speakersMuted: false
		)
		controls.layoutSubtreeIfNeeded()
		#expect(microphone.frame == unmutedFrame)
		#expect(microphone.accessibilityLabel() == "Unmute microphone")
		#expect(microphone.isEnabled && !microphone.hasDestructiveAction)

		let bitmap = try #require(microphone.bitmapImageRepForCachingDisplay(in: microphone.bounds))
		microphone.cacheDisplay(
			in: microphone.bounds,
			to: bitmap
		)
		let fill = try #require(bitmap.colorAt(
			x: bitmap.pixelsWide / 5,
			y: bitmap.pixelsHigh / 2
		)?
			.usingColorSpace(.sRGB))
		#expect(abs(fill.redComponent - 224.0 / 255) < 0.04)
		#expect(abs(fill.greenComponent - 46.0 / 255) < 0.04)
		#expect(bitmap.colorAt(
			x: 0,
			y: 0
		)?.alphaComponent == 0)

		controls.render(
			microphoneMuted: false,
			speakersMuted: false
		)
		#expect(microphone.presentation == .subduedGlyphOnlyIcon)
		#expect(microphone.accessibilityLabel() == "Mute microphone")
	}

	@Test func floatingVoiceOrbKeepsItsArtworkAndEndActionOnHover() throws
	{
		_ = NSApplication.shared
		let controls = VoiceChatControls(floating: true)
		controls.frame.size = NSSize(
			width: 125,
			height: 40
		)
		controls.layoutSubtreeIfNeeded()
		let actions = controls.arrangedSubviews.compactMap
		{
			$0 as? NSButton
		}
		let end = controls.end
		let orb = try #require(controls.orb)
		#expect(actions == [controls.microphone, end, controls.speakers])
		let hover = try #require(NSEvent.enterExitEvent(
			with: .mouseEntered,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: 0,
			context: nil,
			eventNumber: 0,
			trackingNumber: 0,
			userData: nil
		))
		end.mouseEntered(with: hover)
		defer
		{
			end.controlTooltip.dismiss()
		}
		#expect(orb.superview === end && !orb.isHidden)
		#expect(end.image == nil)
		#expect(end.accessibilityLabel() == "End voice chat")
		let center = controls.convert(
			NSPoint(
				x: end.bounds.midX,
				y: end.bounds.midY
			),
			from: end
		)
		#expect(controls.hitTest(center) === end)

		let receiver = ActionReceiver()
		end.target = receiver
		end.action = #selector(ActionReceiver.invoke)
		#expect(end.dispatchConfiguredAction())
		#expect(receiver.calls == 1)
	}

	@Test func voiceOrbGrowsWithPlaybackInsideAFixedLayoutAndResetsWhenInactive() throws
	{
		_ = NSApplication.shared
		let frame = NSRect(
			x: 0,
			y: 0,
			width: 120,
			height: 120
		)
		let window = NSWindow(
			contentRect: frame,
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		defer
		{
			window.close()
		}
		let host = NSView(frame: frame)
		window.contentView = host
		let view = VoiceChatOrb(diameter: 90)
		view.translatesAutoresizingMaskIntoConstraints = false
		host.addSubview(view)
		NSLayoutConstraint.activate([
			view.centerXAnchor.constraint(equalTo: host.centerXAnchor),
			view.centerYAnchor.constraint(equalTo: host.centerYAnchor),
		])
		host.layoutSubtreeIfNeeded()
		let originalFrame = view.frame
		let artwork = try #require(view.layer?.sublayers?.first)

		view.setActive(true)
		let lights = try #require(artwork.sublayers?.compactMap
		{
			$0 as? CAGradientLayer
		})
		let quietLight = lights.map(\.opacity)
		view.setPlaybackLevel(0.25)
		let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
		#expect(lights.contains
		{
			$0.animation(forKey: "orbit") != nil
		} == !reducedMotion)
		#expect((lights.map(\.opacity) != quietLight) == !reducedMotion)
		#expect(abs(artwork.transform.m11 - (reducedMotion ? 1 : 1.08)) < 0.001)
		#expect(artwork.frame.width <= originalFrame.width)
		#expect(view.frame == originalFrame)

		view.setPlaybackLevel(0)
		#expect(artwork.transform.m11 == 1)
		view.setActive(false)
		view.setPlaybackLevel(0.25)
		#expect(artwork.transform.m11 == 1)
		#expect(artwork.animationKeys()?.isEmpty != false)
		#expect(lights.allSatisfy
		{
			$0.animationKeys()?.isEmpty != false
		})
		#expect(lights.map(\.opacity) == quietLight)
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
