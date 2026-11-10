import AppKit
import CoreText
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabFilesIntegrationTests
{
	@Test func newlyVisibleToolContentJoinsKeyboardNavigationWithoutTakingFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 700,
					height: 400
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			defer
			{
				window.close()
			}
			window.autorecalculatesKeyViewLoop = false
			let root = try #require(window.contentView)
			let draft = NSTextField(frame: NSRect(
				x: 10,
				y: 10,
				width: 150,
				height: 28
			))
			draft.stringValue = "Retained draft"
			root.addSubview(draft)
			let tabs = ToolsTabViewController()
			tabs.view.frame = NSRect(
				x: 200,
				y: 0,
				width: 500,
				height: 400
			)
			tabs.view.isHidden = true
			root.addSubview(tabs.view)
			window.recalculateKeyViewLoop()
			#expect(window.makeFirstResponder(draft))
			let editor = try #require(window.firstResponder as? NSTextView)
			let selection = NSRange(
				location: 2,
				length: 4
			)
			editor.setSelectedRange(selection)
			let content = controller()
			let action = KeyboardAction(frame: NSRect(
				x: 10,
				y: 10,
				width: 100,
				height: 28
			))
			content.view.addSubview(action)
			let file = document("visible.swift")
			tabs.updateFileTabs(
				presentations: [file],
				selectedID: file.id,
				controller: content
			)
			tabs.view.isHidden = false
			tabs.setContentVisible(true)
			root.layoutSubtreeIfNeeded()
			#expect(window.firstResponder === editor)
			#expect(editor.selectedRange() == selection)
			#expect(draft.stringValue == "Retained draft")
			var candidate: NSView? = draft
			var visited: Set<ObjectIdentifier> = []
			var reachable = false
			for _ in 0 ..< 30
			{
				guard let next = candidate?.nextValidKeyView,
						visited.insert(ObjectIdentifier(next)).inserted
				else
				{
					break
				}
				if next === action
				{
					reachable = true
					break
				}
				candidate = next
			}
			#expect(reachable)
		}
	}

	@MainActor
	private final class KeyboardAction: NSButton
	{
		override var acceptsFirstResponder: Bool
		{
			true
		}
		override var canBecomeKeyView: Bool
		{
			!isHiddenOrHasHiddenAncestor
		}
	}

	@Test func requestedCloseWaitsForPublishedDocumentRemoval() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let first = document("first.swift")
		let second = document("second.swift")
		let files = controller()
		tabs.updateFileTabs(
			presentations: [first, second],
			selectedID: second.id,
			controller: files
		)
		var requested: [UUID] = []
		tabs.onFileCloseRequested =
		{
			requested.append($0)
		}
		try select(
			"Close tab 1",
			in: tabs.tabBarView
		)
		#expect(requested == [first.id])
		#expect(tabs.tabCount == 2)
		#expect(tabs.selectedFileDocumentID == second.id)
		tabs.updateFileTabs(
			presentations: [second],
			selectedID: second.id,
			controller: files
		)
		#expect(tabs.tabCount == 1)
		#expect(tabs.selectedFileDocumentID == second.id)
		try select(
			"Close tab 1",
			in: tabs.tabBarView
		)
		#expect(tabs.tabCount == 1)
		#expect(requested == [first.id, second.id])
		var closedLast = 0
		tabs.onCloseLastTab =
		{
			closedLast += 1
		}
		tabs.updateFileTabs(
			presentations: [],
			selectedID: nil,
			controller: files
		)
		#expect(tabs.tabCount == 0)
		#expect(closedLast == 1)
	}

	@Test func previewReplacementUsesItsSlotAndSelectionCallbackKeepsIdentity() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let first = document("first.swift")
		let retained = FileToolTabPresentation(
			id: UUID(),
			title: "retained.swift",
			path: "/work/retained.swift",
			isPreview: false,
			isDirty: false
		)
		let replacement = document("replacement.swift")
		let files = controller()
		tabs.updateFileTabs(
			presentations: [first, retained],
			selectedID: first.id,
			controller: files
		)
		tabs.updateFileTabs(
			presentations: [replacement, retained],
			selectedID: replacement.id,
			controller: files
		)
		#expect(tabs.tabCount == 2)
		#expect(button(
			"replacement.swift 1",
			in: tabs.tabBarView
		) != nil)
		var selected: [UUID] = []
		tabs.onFileSelected =
		{
			selected.append($0)
		}
		try select(
			"retained.swift 2",
			in: tabs.tabBarView
		)
		#expect(selected == [retained.id])
		#expect(tabs.selectedFileDocumentID == retained.id)
	}

	@Test func contextActionsCaptureTheirDocumentTargets() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let a = document("a.swift")
		let b = document("b.swift")
		let c = document("c.swift")
		tabs.updateFileTabs(
			presentations: [a, b, c],
			selectedID: a.id,
			controller: controller()
		)
		var closes: [UUID] = []
		var retained: [UUID] = []
		tabs.onFileCloseRequested =
		{
			closes.append($0)
		}
		tabs.onFileRetainRequested =
		{
			retained.append($0)
		}
		let first = try #require(button(
			"a.swift 1",
			in: tabs.tabBarView
		))
		let menu = try #require(first.menu)
		let right = try #require(menu.items.first(where:
			{
				$0.title == "Close to Right"
			}))
		let action = try #require(right.action)
		#expect(NSApp.sendAction(
			action,
			to: right.target,
			from: right
		))
		#expect(closes == [b.id, c.id])
		#expect(tabs.tabCount == 3)
		let keep = try #require(menu.items.first(where:
			{
				$0.title == "Keep Open"
			}))
		let retainAction = try #require(keep.action)
		#expect(NSApp.sendAction(
			retainAction,
			to: keep.target,
			from: keep
		))
		#expect(retained == [a.id])
		let selection = try #require(first as? ToolsTabSelectionButton)
		selection.onDoubleClick?()
		#expect(retained == [a.id, a.id])
	}

	@Test func reorderKeepsDocumentIdentityAndSharedController() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let a = document("a.swift")
		let b = document("b.swift")
		let c = document("c.swift")
		let files = controller()
		tabs.updateFileTabs(
			presentations: [a, b, c],
			selectedID: b.id,
			controller: files
		)
		let third = try #require(button(
			"c.swift 3",
			in: tabs.tabBarView
		))
		let destination = try #require(third.superview as? ToolsTabSurface)
		destination.onDrop?(a.id, false)
		#expect(button(
			"b.swift 1",
			in: tabs.tabBarView
		) != nil)
		#expect(button(
			"c.swift 2",
			in: tabs.tabBarView
		) != nil)
		#expect(button(
			"a.swift 3",
			in: tabs.tabBarView
		) != nil)
		#expect(tabs.selectedFileDocumentID == b.id)
		#expect(files.parent === tabs)
		tabs.updateFileTabs(
			presentations: [a, b, c],
			selectedID: b.id,
			controller: files
		)
		#expect(button(
			"a.swift 3",
			in: tabs.tabBarView
		) != nil)
		#expect(files.parent === tabs)
	}

	@Test func imageTabsSurviveOtherToolSelectionAndCloseIndependently() throws
	{
		let tabs = ToolsTabViewController()
		tabs.showImageTab(
			data: Data(),
			name: "attachment.png"
		)
		let imageID = try #require(tabs.selectedTabID)
		#expect(tabs.tabCount == 1)
		let imageController = try #require(tabs.children.first as? ExpandedImageViewController)
		let files = controller()
		tabs.showFilesLanding(files)
		#expect(tabs.tabCount == 2)
		#expect(imageController.view.isHidden)
		try select(
			"attachment.png 1",
			in: tabs.tabBarView
		)
		#expect(tabs.selectedTabID == imageID)
		#expect(!imageController.view.isHidden)
		let close = try #require(button(
			"Close tab 1",
			in: tabs.tabBarView
		))
		let action = try #require(close.action)
		#expect(NSApp.sendAction(
			action,
			to: close.target,
			from: close
		))
		#expect(imageController.parent == nil)
		#expect(tabs.tabCount == 1)
	}

	@Test func imageTabContextMenuOpensAnotherIndependentTab() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let tabs = ToolsTabViewController()
			let bitmap = try #require(NSBitmapImageRep(
				bitmapDataPlanes: nil,
				pixelsWide: 1,
				pixelsHigh: 1,
				bitsPerSample: 8,
				samplesPerPixel: 4,
				hasAlpha: true,
				isPlanar: false,
				colorSpaceName: .deviceRGB,
				bytesPerRow: 4,
				bitsPerPixel: 32
			))
			bitmap.setColor(
				.red,
				atX: 0,
				y: 0
			)
			let data = try #require(bitmap.representation(
				using: .png,
				properties: [:]
			))
			tabs.showImageTab(
				data: data,
				name: "attachment.png",
				sourceURL: URL(fileURLWithPath: "/tmp/attachment.png")
			)
			let firstID = try #require(tabs.selectedTabID)
			let firstController = try #require(tabs.children.first as? ExpandedImageViewController)
			await tabs.waitForImageTab(firstID)
			let image = firstController.imageView
			let event = try #require(NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: 0,
				context: nil,
				eventNumber: 0,
				clickCount: 1,
				pressure: 1
			))
			let menu = try #require(image.menu(for: event))
			#expect(menu.items.map(\.title) == [
				"Open image in new tab",
				"Copy image",
				"Reveal in Finder",
				"Download a copy"
			])
			#expect(menu.items.filter
			{
				!$0.isEnabled
			}.isEmpty)
			let open = menu.items[0]
			let action = try #require(open.action)
			#expect(NSApp.sendAction(
				action,
				to: open.target,
				from: open
			))
			#expect(tabs.tabCount == 2)
			#expect(tabs.selectedTabID != firstID)
			#expect(firstController.parent === tabs)
			let secondController = try #require(tabs.children.last as? ExpandedImageViewController)
			let secondID = try #require(tabs.selectedTabID)
			await tabs.waitForImageTab(secondID)
			let secondImage = secondController.imageView
			let secondMenu = try #require(secondImage.menu(for: event))
			#expect(secondMenu.items[2].isEnabled)
		}
	}

	private func document(_ name: String) -> FileToolTabPresentation
	{
		FileToolTabPresentation(
			id: UUID(),
			title: name,
			path: "/work/\(name)",
			isPreview: true,
			isDirty: false
		)
	}

	private func controller() -> NSViewController
	{
		let controller = NSViewController()
		controller.view = NSView()
		return controller
	}

	private func select(
		_ label: String,
		in view: NSView
	) throws
	{
		let control = try #require(button(
			label,
			in: view
		))
		let action = try #require(control.action)
		#expect(NSApp.sendAction(
			action,
			to: control.target,
			from: control
		))
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

	private func scrollView(in view: NSView) -> NSScrollView?
	{
		if let scroll = view as? NSScrollView
		{
			return scroll
		}
		return view.subviews.lazy.compactMap
		{
			scrollView(in: $0)
		}.first
	}
}

@Suite
struct ToolsTabDragPayloadTests
{
	@Test func foreignAndSpoofedPayloadsCannotMoveTabs()
	{
		let owner = UUID()
		let tab = UUID()
		let payload = ToolsTabDragPayload(
			ownerID: owner,
			tabID: tab
		)
		#expect(ToolsTabDragPayload(string: payload.string) == payload)
		#expect(payload.isOwned(
			by: owner,
			source: payload
		))
		#expect(!payload.isOwned(
			by: UUID(),
			source: payload
		))
		#expect(!payload.isOwned(
			by: owner,
			source: ToolsTabDragPayload(
				ownerID: owner,
				tabID: UUID()
			)
		))
		#expect(ToolsTabDragPayload(string: "malformed") == nil)
	}
}
