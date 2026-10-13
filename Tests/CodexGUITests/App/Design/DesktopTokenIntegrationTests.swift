import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct DesktopTokenIntegrationTests
{
	@Test func sharedControlStylesKeepTheExistingNativeFonts()
	{
		let button = NSButton(
			title: "Action",
			target: nil,
			action: nil
		)
		AppKitControlStyling.styleButton(button)
		#expect(button.font == NSFont.systemFont(ofSize: 12))
		AppKitControlStyling.styleButton(
			button,
			prominent: true
		)
		#expect(button.font == NSFont.systemFont(
			ofSize: 12,
			weight: .medium
		))
		#expect(AppKitControlStyling.sectionLabel("Section").font
			== NSFont.systemFont(
				ofSize: 11,
				weight: .medium
			))
	}

	@Test func extractedSurfaceKeepsNativeOpacityBehavior()
	{
		let flat = DesktopSurface(.white)
		let rounded = DesktopSurface(
			.white,
			cornerRadius: 16
		)
		#expect(!flat.isOpaque)
		#expect(!rounded.isOpaque)
	}

	@Test func existingDynamicPaletteResolvesUnderTheOwningAppearance() throws
	{
		let owner = NSView()
		owner.appearance = NSAppearance(named: .darkAqua)
		let resolved = AppKitColorResolution.resolvedCGColor(
			AppKitColorTokens.userBubble,
			for: owner
		)
		let color = try #require(NSColor(cgColor: resolved)?.usingColorSpace(.sRGB))
		#expect(abs(color.redComponent - 34 / 255.0) < 0.001)
		#expect(abs(color.greenComponent - 61 / 255.0) < 0.001)
		#expect(abs(color.blueComponent - 114 / 255.0) < 0.001)
	}
	@Test func footerSwitchesModesRepeatedlyUsingItsActualInnerWidth() throws
	{
		_ = NSApplication.shared
		let leading = NSView()
		let preference = NSView()
		let actions = NSView()
		for group in [leading, preference, actions]
		{
			group.heightAnchor.constraint(equalToConstant: 28).isActive = true
			group.widthAnchor.constraint(equalToConstant: 28).isActive = true
		}
		let footer = ComposerToolbarView(
			leadingControls: leading,
			preferenceControl: preference,
			actionControls: actions
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 500,
				height: 28
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentView = footer
		defer
		{
			window.close()
		}
		for width: CGFloat in [500, 432, 440, 432, 500]
		{
			window.setContentSize(NSSize(
				width: width,
				height: width < 440 ? 60 : 28
			))
			window.layoutIfNeeded()
			footer.needsLayout = true
			footer.layoutSubtreeIfNeeded()
			let preferenceFrame = footer.convert(
				preference.bounds,
				from: preference
			)
			let actionFrame = footer.convert(
				actions.bounds,
				from: actions
			)
			#expect(abs(preferenceFrame.midY - actionFrame.midY) < 0.01)
			#expect(footer.fittingSize.height == (width < 440 ? 60 : 28))
		}
	}

	@Test func independentComposerInsetsSettleInsideAnAttachedStack() throws
	{
		_ = NSApplication.shared
		for footerInset: CGFloat in [8, 12, 16]
		{
			let metrics = LayoutTokens.Composer(footerHorizontalInset: footerInset)
			let surface = NSView()
			let editor = NSView()
			let footer = NSView()
			let attachments = NSView()
			attachments.isHidden = true
			editor.heightAnchor.constraint(equalToConstant: 44).isActive = true
			footer.heightAnchor.constraint(equalToConstant: 28).isActive = true
			ComposerSurfaceLayout.install(
				in: surface,
				attachments: attachments,
				editor: editor,
				footer: footer,
				metrics: metrics
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 500,
					height: 98
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = surface
			defer
			{
				window.close()
			}
			window.layoutIfNeeded()
			surface.layoutSubtreeIfNeeded()
			let editorFrame = surface.convert(
				editor.bounds,
				from: editor
			)
			let footerFrame = surface.convert(
				footer.bounds,
				from: footer
			)
			#expect(editorFrame.minX == 12)
			#expect(editorFrame.width == 476)
			#expect(footerFrame.minX == footerInset)
			#expect(footerFrame.width == 500 - 2 * footerInset)
			#expect(editorFrame.midX == footerFrame.midX)
		}
	}

}
