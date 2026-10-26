import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsPageLayoutTests
{
	@Test func emptyStatusDoesNotAddSectionSpacingAndReappearsWhenPopulated() throws
	{
		_ = NSApplication.shared
		let first = NSView()
		let second = NSView()
		for section in [first, second]
		{
			section.heightAnchor.constraint(equalToConstant: 40).isActive = true
		}
		let status = SettingsPageLayout.status("")
		let page = SettingsPageLayout.document(
			title: "Settings",
			sections: [first, status, second]
		)
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1000,
				height: 700
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = page
		defer
		{
			window.close()
		}

		func gap() -> CGFloat
		{
			window.layoutIfNeeded()
			page.layoutSubtreeIfNeeded()
			let upper = first.convert(
				first.bounds,
				to: page
			)
			let lower = second.convert(
				second.bounds,
				to: page
			)
			return upper.minY - lower.maxY
		}

		#expect(abs(gap() - LayoutTokens.Connections.sectionGap) < 1)
		status.stringValue = "Saved successfully."
		#expect(gap() > 2 * LayoutTokens.Connections.sectionGap)
		status.stringValue = ""
		#expect(abs(gap() - LayoutTokens.Connections.sectionGap) < 1)
		window.setContentSize(NSSize(
			width: 760,
			height: 600
		))
		#expect(abs(gap() - LayoutTokens.Connections.sectionGap) < 1)
	}

	@Test func fixedAndViewportColumnsKeepTheirExistingWidthPolicies() throws
	{
		_ = NSApplication.shared
		for policy: SettingsPageLayout.ColumnWidth in [.fixed, .fitsViewport]
		{
			let section = NSView()
			section.heightAnchor.constraint(equalToConstant: 40).isActive = true
			let stack = AppKitLayout.verticalStack([section])
			section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
			let page = SettingsPageLayout.document(
				content: stack,
				columnWidth: policy
			)
			let window = makeWindow(page: page)
			defer
			{
				window.close()
			}
			window.layoutIfNeeded()
			page.layoutSubtreeIfNeeded()
			#expect(abs(page.bounds.width - 1000) < 1)
			let scroll = try #require(stack.enclosingScrollView)
			let document = try #require(scroll.documentView)
			#expect(abs(document.bounds.width - scroll.contentView.bounds.width) < 1)
			#expect(abs(stack.frame.width - LayoutTokens.Connections.contentWidth) < 1)
			if case .fitsViewport = policy
			{
				window.setContentSize(NSSize(
					width: 600,
					height: 600
				))
				window.layoutIfNeeded()
				page.layoutSubtreeIfNeeded()
				let viewport = try #require(stack.enclosingScrollView?.contentView)
				#expect(abs(stack.frame.width - (viewport.bounds.width - 40)) < 1)
				#expect(abs(stack.frame.minX - 20) < 1)
				#expect(abs(stack.frame.minY - LayoutTokens.Connections.topInset) < 1)
			}
		}
	}


	@Test func readOnlyValueRowsUpdateTheirRetainedValueWithoutChangingRowGeometry() throws
	{
		_ = NSApplication.shared
		let row = SettingsReadOnlyValueRow(
			title: "Email",
			value: "Checking…"
		)
		row.widthAnchor.constraint(equalToConstant: 500).isActive = true
		row.layoutSubtreeIfNeeded()
		let value = try #require(descendants(row).compactMap
		{
			$0 as? NSTextField
		}.first
		{
			$0.accessibilityLabel() == "Email" && $0.stringValue == "Checking…"
		})
		row.setValue(
			"person@example.com",
			help: "Account email"
		)
		#expect(value.stringValue == "person@example.com")
		#expect(value.toolTip == "Account email")
		#expect(value.alignment == .right)
		#expect(!value.isEditable)
		#expect(abs(row.fittingSize.height - 50) < 1)
	}

	@Test func completePageKeepsAppendedSectionsInItsRetainedReadingColumn() throws
	{
		_ = NSApplication.shared
		let first = NSView()
		first.heightAnchor.constraint(equalToConstant: 40).isActive = true
		let page = SettingsPageLayout.document(
			title: "General",
			sections: [first],
			columnWidth: .fitsViewport
		)
		let window = makeWindow(page: page)
		defer
		{
			window.close()
		}
		let additional = NSView()
		additional.heightAnchor.constraint(equalToConstant: 50).isActive = true
		page.appendSection(additional)
		window.setContentSize(NSSize(
			width: 600,
			height: 600
		))
		window.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		let viewport = try #require(first.enclosingScrollView?.contentView)
		#expect(first.window === window && additional.window === window)
		#expect(first.superview === additional.superview)
		#expect(abs(first.frame.width - (viewport.bounds.width - 40)) < 1)
		#expect(abs(additional.frame.width - first.frame.width) < 1)
		#expect(descendants(page).compactMap
		{
			$0 as? NSTextField
		}.contains
		{
			$0.stringValue == "General" && $0.font?.pointSize == 28
		})
	}

	private func makeWindow(page: NSView) -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1000,
				height: 700
			),
			styleMask: [.titled, .resizable],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = page
		return window
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}

}
