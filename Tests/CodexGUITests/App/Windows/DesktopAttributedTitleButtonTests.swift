import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct DesktopAttributedTitleButtonTests
{
	@Test func retainedMixedTitlesFollowInheritedAppearanceAndPreserveButtonState() throws
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		window.appearance = NSAppearance(named: .aqua)
		let parent = NSView(frame: window.contentView!.bounds)
		window.contentView?.addSubview(parent)
		let button = DesktopAttributedTitleButton(frame: NSRect(
			x: 10,
			y: 10,
			width: 180,
			height: 30
		))
		let cell = NSButtonCell(textCell: "")
		button.cell = cell
		button.setButtonType(.pushOnPushOff)
		button.isBordered = false
		button.state = .on
		button.setAccessibilityLabel("Retained action")
		let font = NSFont.systemFont(
			ofSize: 13,
			weight: .medium
		)
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		let title = NSMutableAttributedString(
			string: "Action +7",
			attributes: [
				.font: font,
				.paragraphStyle: paragraph,
				.foregroundColor: NSColor.labelColor,
			]
		)
		title.addAttribute(
			.foregroundColor,
			value: NSColor.systemGreen,
			range: NSRange(
				location: 7,
				length: 2
			)
		)
		let alternate = NSAttributedString(
			string: "Selected",
			attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
		)
		let dark = try #require(NSAppearance(named: .darkAqua))
		dark.performAsCurrentDrawingAppearance
		{
			button.attributedTitle = title
			button.attributedAlternateTitle = alternate
			parent.addSubview(button)
		}
		#expect(window.makeFirstResponder(button))
		let frame = button.frame
		var colors: [CGColor] = []
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua, .darkAqua, .aqua]
		{
			let ambient = try #require(NSAppearance(named: name == .aqua ? .darkAqua : .aqua))
			ambient.performAsCurrentDrawingAppearance
			{
				parent.appearance = NSAppearance(named: name)
			}
			try expectColor(
				.labelColor,
				at: 0,
				in: button.attributedTitle,
				button: button
			)
			try expectColor(
				.systemGreen,
				at: 7,
				in: button.attributedTitle,
				button: button
			)
			try expectColor(
				.secondaryLabelColor,
				at: 0,
				in: button.attributedAlternateTitle,
				button: button
			)
			let foreground = try #require(button.attributedTitle.attribute(
				.foregroundColor,
				at: 0,
				effectiveRange: nil
			) as? NSColor)
			colors.append(foreground.cgColor)
			#expect(button.attributedTitle.string == title.string)
			#expect(button.attributedAlternateTitle.string == alternate.string)
			#expect(button.attributedTitle
				.attribute(
					.font,
					at: 0,
					effectiveRange: nil
				) as? NSFont == font)
			#expect(button.attributedTitle.attribute(
				.paragraphStyle,
				at: 0,
				effectiveRange: nil
			) as? NSParagraphStyle == paragraph)
			#expect(button.cell === cell)
			#expect(button.state == .on)
			#expect(button.frame == frame)
			#expect(button.accessibilityLabel() == "Retained action")
			#expect(window.firstResponder === button)
		}
		#expect(colors[0] != colors[1])
		#expect(colors[0] == colors[2])
	}

	@Test func plainTitleReplacementDoesNotRestoreObsoleteAttributedContent()
	{
		_ = NSApplication.shared
		let window = makeWindow()
		defer
		{
			window.close()
		}
		let button = DesktopAttributedTitleButton()
		window.contentView?.addSubview(button)
		button.attributedTitle = NSAttributedString(
			string: "Old",
			attributes: [.foregroundColor: NSColor.labelColor]
		)
		button.attributedAlternateTitle = NSAttributedString(
			string: "Old alternate",
			attributes: [.foregroundColor: NSColor.secondaryLabelColor]
		)
		button.title = "Replacement"
		button.alternateTitle = "Replacement alternate"
		for name: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
		{
			window.appearance = NSAppearance(named: name)
			#expect(button.title == "Replacement")
			#expect(button.alternateTitle == "Replacement alternate")
		}
	}

	private func expectColor(
		_ color: NSColor,
		at index: Int,
		in title: NSAttributedString,
		button: DesktopAttributedTitleButton
	) throws
	{
		let actual = try #require(title.attribute(
			.foregroundColor,
			at: index,
			effectiveRange: nil
		) as? NSColor)
		#expect(actual.cgColor == DesktopTheme.resolvedCGColor(
			color,
			for: button
		))
	}

	private func makeWindow() -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: -2000,
				y: -2000,
				width: 300,
				height: 100
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		return window
	}
}
