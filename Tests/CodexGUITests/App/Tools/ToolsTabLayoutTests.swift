import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabLayoutTests
{
	@Test(arguments: [false, true])
	func minimumToolbarWidthKeepsTabButtonsAtFullWidth(expanded: Bool) throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		tabs.setExpanded(expanded)
		let header = tabs.tabBarView
		let width = tabs.minimumTabBarWidth
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: width,
				height: 60
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		defer
		{
			window.close()
		}
		let content = try #require(window.contentView)
		header.translatesAutoresizingMaskIntoConstraints = false
		content.addSubview(header)
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor),
			header.topAnchor.constraint(equalTo: content.topAnchor),
			header.widthAnchor.constraint(equalToConstant: width),
			header.heightAnchor.constraint(equalToConstant: 28),
		])
		window.layoutIfNeeded()
		header.layoutSubtreeIfNeeded()

		let scrollView = try #require(descendant(
			NSScrollView.self,
			in: header
		))
		let selection = try #require(button(
			"New tab 1",
			in: header
		))
		let close = try #require(button(
			"Close tab 1",
			in: header
		))
		let tab = try #require(close.superview)
		#expect(scrollView.contentView.bounds.width >= 64)
		#expect(selection.frame.width >= 24)
		#expect(close.frame.width == 24)
		#expect(selection.frame.minX >= tab.bounds.minX)
		#expect(close.frame.maxX <= tab.bounds.maxX)
	}

	private func descendant<View: NSView>(
		_ type: View.Type,
		in view: NSView
	) -> View?
	{
		if let match = view as? View
		{
			return match
		}
		return view.subviews.lazy.compactMap
		{
			descendant(
				type,
				in: $0
			)
		}.first
	}

	private func button(
		_ label: String,
		in view: NSView
	) -> NSButton?
	{
		if let button = view as? NSButton, button.accessibilityLabel() == label
		{
			return button
		}
		return view.subviews.lazy.compactMap
		{
			button(
				label,
				in: $0
			)
		}.first
	}
}
