import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.serialized)
struct DesktopPopoverHostTests
{
	@Test func composerPanelClicksUseTheirEventWindowBeforeTheAmbientPointer() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let controller = NSViewController()
			controller.view = NSView()
			controller.preferredContentSize = NSSize(
				width: 300,
				height: 200
			)
			let host = DesktopPopoverHost(
				presentation: .composer(DesktopPopoverHost.ComposerPlacement()),
				content: controller.view,
				controller: controller
			)
			defer
			{
				host.close(); window.close()
			}
			host.show(from: anchor)
			let pointer = NSEvent.mouseLocation
			host.panel.setFrameOrigin(NSPoint(
				x: pointer.x + 1000,
				y: pointer.y + 1000
			))
			let click = try #require(NSEvent.mouseEvent(
				with: .leftMouseDown,
				location: NSPoint(
					x: 20,
					y: 20
				),
				modifierFlags: [],
				timestamp: 0,
				windowNumber: host.panel.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			))
			#expect(host.shouldForward(click))
			#expect(host.isShown)
		}
	}

	@Test func detachingTheAnchorDismissesTheSharedHostWithoutTakingForeignFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let content = NSView()
			let host = DesktopPopoverHost(
				presentation: .account,
				content: content
			)
			var changes: [Bool] = []
			host.onPresentationChange =
			{
				changes.append($0)
			}
			defer
			{
				host.close(); window.close()
			}
			host.show(from: anchor)
			#expect(host.isShown)
			#expect(host.panel.parent === window)
			anchor.removeFromSuperview()
			#expect(!host.isShown)
			#expect(host.panel.parent == nil)
			#expect(!host.panel.isVisible)
			#expect(changes == [true, false])
			host.close()
			#expect(changes == [true, false])
		}
	}

	@Test func materialMenuAndSearchShareDismissalButKeepTheirParentClickPolicy() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			defer
			{
				window.close()
			}
			for presentation: DesktopPopoverHost.Presentation in [
				.account,
				.search(
					placement: .centered,
					size: NSSize(
						width: 300,
						height: 200
					)
				)
			]
			{
				let controller = NSViewController()
				controller.view = NSView()
				let host = DesktopPopoverHost(
					presentation: presentation,
					content: controller.view,
					controller: controller
				)
				defer
				{
					host.close()
				}
				host.show(from: anchor)
				let click = try #require(NSEvent.mouseEvent(
					with: .leftMouseDown,
					location: NSPoint(
						x: 200,
						y: 100
					),
					modifierFlags: [],
					timestamp: 0,
					windowNumber: window.windowNumber,
					context: nil,
					eventNumber: 1,
					clickCount: 1,
					pressure: 1
				))
				let forwarded = host.shouldForward(click)
				if case .account = presentation
				{
					#expect(forwarded)
				}
				else
				{
					#expect(!forwarded)
				}
				#expect(!host.isShown)
				#expect(host.panel.parent == nil)
			}
		}
	}

	@Test func menuTypeaheadSkipsDisabledRowsCyclesAndNeverInvokesAnAction() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let content = NSView()
			let rows = ["Alpha", "Bravo", "Broom"].map
			{
				DesktopMenuRow(content: DesktopMenuRow.Content(title: $0))
			}
			var invocations = 0
			for (index, row) in rows.enumerated()
			{
				row.frame = NSRect(
					x: 0,
					y: CGFloat(index) * row.rowHeight,
					width: 200,
					height: row.rowHeight
				)
				content.addSubview(row)
				row.onInvoke =
				{
					invocations += 1
				}
			}
			rows[1].isEnabled = false
			let host = DesktopPopoverHost(
				presentation: .account,
				content: content
			)
			host.typeaheadRows =
			{
				rows
			}
			defer
			{
				host.close(); window.close()
			}
			host.show(from: anchor)
			host.panel.makeFirstResponder(rows[0])
			for (timestamp, expected) in [(1.0, 2), (1.1, 1)]
			{
				let key = try #require(NSEvent.keyEvent(
					with: .keyDown,
					location: .zero,
					modifierFlags: [],
					timestamp: timestamp,
					windowNumber: host.panel.windowNumber,
					context: nil,
					characters: "b",
					charactersIgnoringModifiers: "b",
					isARepeat: false,
					keyCode: 11
				))
				#expect(!host.shouldForward(key))
				#expect(host.panel.firstResponder === rows[expected])
				rows[1].isEnabled = true
			}
			#expect(invocations == 0)
			#expect(host.isShown)
		}
	}

	@Test func detachedPresentationRequestsLeaveTheCurrentMenusIntact() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			let detached = NSButton()
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let account = AccountMenuPanel(content: StatusPopoverView(frame: .zero))
			let choices = SettingsChoiceMenu(
				choices: [SettingsChoicePicker.Choice(
					id: "one",
					title: "One"
				)],
				selectedID: "one",
				accessibilityLabel: "Choices"
			)
			defer
			{
				account.close(); choices.close(); window.close()
			}
			account.show(from: anchor)
			let accountPanel = try #require(account.content.window)
			account.show(from: detached)
			#expect(account.isShown)
			#expect(account.content.window === accountPanel)
			#expect(accountPanel.parent === window)
			account.close()
			choices.show(from: anchor)
			let choicePanel = try #require(window.childWindows?.first)
			choices.show(from: detached)
			#expect(choices.isShown)
			#expect(choicePanel.parent === window)
			#expect(choicePanel.isVisible)
		}
	}

	@Test func menuAndSearchContentHitTestingUsesTheWindowContentCoordinates() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			defer
			{
				window.close()
			}
			for presentation: DesktopPopoverHost.Presentation in [
				.account,
				.search(
					placement: .centered,
					size: NSSize(
						width: 300,
						height: 200
					)
				)
			]
			{
				let controller = NSViewController()
				controller.view = NSView()
				let row = DesktopMenuRow(content: DesktopMenuRow.Content(title: "Settings"))
				row.frame = NSRect(
					x: 8,
					y: 20,
					width: 180,
					height: row.rowHeight
				)
				controller.view.addSubview(row)
				let host = DesktopPopoverHost(
					presentation: presentation,
					content: controller.view,
					controller: controller
				)
				defer
				{
					host.close()
				}
				host.show(from: anchor)
				let content = try #require(host.panel.contentView)
				content.layoutSubtreeIfNeeded()
				let point = row.convert(
					NSPoint(
						x: row.bounds.midX,
						y: row.bounds.midY
					),
					to: content
				)
				#expect(content.hitTest(point) === row)
			}
		}
	}

	@Test func inlineSuggestionsReceiveOneOpaqueHostSurfaceAndKeepTheirRowViewport() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSButton(frame: NSRect(
				x: 20,
				y: 20,
				width: 28,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let suggestions = SlashCommandPopoverView()
			suggestions.render(prefix: "sta")
			let host = ComposerPopoverPanel(contentViewController: suggestions)
			defer
			{
				host.close(); window.close()
			}
			host.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			let panel = try #require(suggestions.view.window)
			let surface = try #require(suggestions.view.superview as? DesktopSurface)
			panel.contentView?.layoutSubtreeIfNeeded()
			let contentBounds = suggestions.view.convert(
				suggestions.view.bounds,
				to: surface
			)
			#expect(abs(contentBounds.minX - 4) < 0.01)
			#expect(abs(contentBounds.minY - 4) < 0.01)
			#expect(abs(surface.bounds.width - contentBounds.maxX - 4) < 0.01)
			#expect(abs(surface.bounds.height - contentBounds.maxY - 4) < 0.01)
			#expect(abs(panel.frame.height - 36) < 0.01)
			#expect(suggestions.selectedCommand?.id == .status)
		}
	}

	@Test func composerSuggestionsKeepTrailingAccessoriesVisibleAcrossWidthChanges() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = makeWindow()
			let anchor = NSView(frame: NSRect(
				x: 10,
				y: 20,
				width: 540,
				height: 28
			))
			window.contentView?.addSubview(anchor)
			window.makeKeyAndOrderFront(nil)
			let suggestions = SlashCommandPopoverView()
			suggestions.availableSkills = [try #require(AvailableSkill(json: [
				"name": "documents",
				"description": String(
					repeating: "A long document description ",
					count: 20
				),
				"path": "/skills/documents",
				"scope": "user",
				"enabled": true,
				"interface": ["displayName": "Documents"],
			]))]
			suggestions.render(prefix: "")
			let host = ComposerPopoverPanel(contentViewController: suggestions)
			host.matchesAnchorWidth = true
			defer
			{
				host.close(); window.close()
			}
			host.show(
				relativeTo: anchor.bounds,
				of: anchor
			)
			let panel = try #require(suggestions.view.window)
			let scroll = try #require(descendants(suggestions.view)
				.compactMap
				{
					$0 as? NSScrollView
				}.first)
			let table = try #require(scroll.documentView as? SlashCommandMenuTableView)
			let pickerRow = try #require(suggestions.commands
				.firstIndex
				{
					SlashCommandMenuPresentation($0.id).opensPicker
				})
			suggestions.moveSelection(by: 1)
			let selected = table.selectedRow
			for width: CGFloat in [736, 300, 736]
			{
				anchor.setFrameSize(NSSize(
					width: width,
					height: 28
				))
				host.show(
					relativeTo: anchor.bounds,
					of: anchor
				)
				panel.contentView?.layoutSubtreeIfNeeded()
				#expect(abs(panel.frame.width - width) < 0.01)
				for row in [pickerRow, table.numberOfRows - 1]
				{
					table.scrollRowToVisible(row)
					let cell = try #require(table.view(
						atColumn: 0,
						row: row,
						makeIfNecessary: true
					))
					panel.contentView?.layoutSubtreeIfNeeded()
					let content = try #require(descendants(cell)
						.compactMap
						{
							$0 as? DesktopSearchResultContentView
						}.first)
					let accessory = try #require(descendants(content).first
					{
						if let label = $0 as? NSTextField
						{
							return label.stringValue == "Personal"
						}
						return $0 is NSImageView && abs($0.bounds.width - 10) < 0.01
					})
					let visible = scroll.contentView.bounds
					let bounds = accessory.convert(
						accessory.bounds,
						to: scroll.contentView
					)
					let panelBounds = accessory.convert(
						accessory.bounds,
						to: panel.contentView
					)
					#expect(panelBounds.maxX <= panel.contentView!.bounds.maxX - 12)
					#expect(bounds.minX >= visible.minX)
					#expect(bounds.maxX <= visible.maxX - 8)
					#expect(abs(table.bounds.width - visible.width) < 0.01)
					#expect(abs(table.tableColumns[0].width - visible.width) < 0.01)
					if row == table.numberOfRows - 1
					{
						let label = try #require(accessory as? NSTextField)
						#expect(label.bounds.width >= label.intrinsicContentSize.width - 0.5)
						#expect(content.detailLabel.bounds.width < content.detailLabel
							.intrinsicContentSize.width)
						#expect(content.detailLabel.lineBreakMode == .byTruncatingTail)
					}
					#expect(table.selectedRow == selected)
				}
			}
			table.scrollRowToVisible(table.selectedRow)
			suggestions.moveSelection(by: 1)
			#expect(table.selectedRow == selected + 1)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}

	private func makeWindow() -> NSWindow
	{
		let window = NSWindow(
			contentRect: NSRect(
				x: 200,
				y: 200,
				width: 600,
				height: 400
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		return window
	}
}
