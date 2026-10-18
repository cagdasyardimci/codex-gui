import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct ViewerToolbarControlsTests
{
	@Test func controlsRetainActionsAndLayoutAcrossAppearanceChanges() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let receiver = Receiver()
			let icon = DesktopIcons.image(.folders)
			let capsule = ViewerToolbarButton(
				title: "Open",
				target: receiver,
				action: #selector(Receiver.activate(_:))
			)
			capsule.image = icon
			capsule.imagePosition = .imageLeading
			capsule.trailingImage = DesktopIcons.image(.chevronDown)
			capsule.setAccessibilityLabel("Open file actions")
			capsule.toolTip = "Open file actions"
			let grouped = ViewerToolbarButton.icon(
				"Toggle navigator",
				image: icon,
				target: receiver,
				action: #selector(Receiver.activate(_:))
			)
			let group = ViewerToolbarGroup(
				grouped,
				horizontalInset: 6,
				verticalInset: 3
			)
			let stack = AppKitLayout.horizontalStack(
				[capsule, group],
				spacing: 8
			)
			let host = DesktopSurface(AppKitColorTokens.canvas)
			host.addSubview(stack)
			stack.translatesAutoresizingMaskIntoConstraints = false
			NSLayoutConstraint.activate([
				stack.leadingAnchor.constraint(
					equalTo: host.leadingAnchor,
					constant: 20
				),
				stack.topAnchor.constraint(
					equalTo: host.topAnchor,
					constant: 20
				)
			])
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 400,
					height: 120
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = host
			defer
			{
				window.close()
			}
			var previousGeometry: [NSRect]?
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				host.layoutSubtreeIfNeeded()
				#expect(capsule.bounds.height == 34)
				#expect(grouped.bounds.size == NSSize(
					width: 28,
					height: 28
				))
				#expect(capsule.bounds.width > 70)
				#expect(capsule.frame.maxX <= group.frame.minX)
				let geometry = [capsule.frame, group.frame, grouped.frame]
				if let previousGeometry
				{
					#expect(geometry == previousGeometry)
				}
				previousGeometry = geometry
				for button in [capsule, grouped]
				{
					#expect(button.accessibilityLabel()?.isEmpty == false)
					let before = receiver.activations
					#expect(button.dispatchConfiguredAction())
					#expect(receiver.activations == before + 1)
					button.isEnabled = false
					#expect(!button.dispatchConfiguredAction())
					#expect(receiver.activations == before + 1)
					button.isEnabled = true
				}
				if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
				{
					try AppTestPNGWriter.write(
						host,
						to: URL(fileURLWithPath: directory)
							.appendingPathComponent("toolbar-controls-\(appearance.rawValue).png")
					)
				}
			}
		}
	}

	@Test func capsuleSelectedPressedAndDisabledStatesHaveDistinctRendering() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let button = ViewerToolbarButton(
				title: "",
				target: nil,
				action: nil
			)
			button.image = DesktopIcons.image(.folders)
			button.showsSelection = true
			button.setButtonType(.toggle)
			let host = DesktopSurface(AppKitColorTokens.canvas)
			button.frame = NSRect(
				x: 20,
				y: 20,
				width: 34,
				height: 34
			)
			host.addSubview(button)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 100,
					height: 90
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = host
			defer
			{
				window.close()
			}
			for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				button.state = .off
				let normal = try pixels(button)
				button.state = .on
				let selected = try pixels(button)
				#expect(normal != selected)
				button.highlight(true)
				let pressed = try pixels(button)
				#expect(pressed != selected)
				button.highlight(false)
				button.isEnabled = false
				let disabled = try pixels(button)
				#expect(disabled != selected)
				#expect(button.state == .on)
				button.isEnabled = true
			}
		}
	}

	private func pixels(_ view: NSView) throws -> Data
	{
		let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
		view.cacheDisplay(
			in: view.bounds,
			to: image
		)
		return try #require(image.representation(
			using: .png,
			properties: [:]
		))
	}

	@MainActor private final class Receiver: NSObject
	{
		var activations = 0
		@objc func activate(_ sender: NSButton)
		{
			activations += 1
		}
	}
}
