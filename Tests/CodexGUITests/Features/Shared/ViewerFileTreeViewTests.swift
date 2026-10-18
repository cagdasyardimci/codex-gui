import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerFileTreeViewTests
{
	@MainActor private final class Item: NSObject
	{
		let path: String
		let directory: Bool

		init(
			_ path: String,
			directory: Bool
		)
		{
			self.path = path
			self.directory = directory
		}
	}

	@Test func navigatorSurfaceHostsFilterAndAutohidingTreeScroll() throws
	{
		_ = NSApplication.shared
		let filter = ViewerSearchField()
		let tree = ViewerFileTreeView()
		let status = NSTextField(labelWithString: "")
		status.isHidden = true
		let navigator = ViewerFileNavigatorView(
			filterField: filter,
			tree: tree,
			statusView: status
		)
		#expect(navigator.scrollView.documentView === tree)
		#expect(navigator.scrollView.hasVerticalScroller)
		#expect(navigator.scrollView.autohidesScrollers)
		#expect(!navigator.scrollView.drawsBackground)
		let stack = try #require(navigator.subviews.first as? NSStackView)
		#expect(stack.arrangedSubviews.contains(filter))
		#expect(stack.arrangedSubviews.contains(status))
		#expect(stack.arrangedSubviews.contains(navigator.scrollView))
	}

	@Test func configuredControlOwnsDisclosureKeyboardAndContextTargeting() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let folder = Item(
				"Sources",
				directory: true
			)
			let file = Item(
				"Sources/Main.swift",
				directory: false
			)
			let tree = ViewerFileTreeView()
			let scroll = NSScrollView(frame: NSRect(
				x: 0,
				y: 0,
				width: 260,
				height: 160
			))
			scroll.documentView = tree
			let window = NSWindow(
				contentRect: scroll.frame,
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = scroll
			defer
			{
				window.close()
			}
			var activated: [(String, Bool)] = []
			var menuTarget: String?
			tree.rootItems = [folder]
			tree.children =
			{
				item in item === folder ? [file] : []
			}
			tree.isExpandable =
			{
				($0 as? Item)?.directory == true
			}
			tree.presentation =
			{
				item in
				let node = item as! Item
				return ViewerFileTreePresentation(
					name: (node.path as NSString).lastPathComponent,
					path: node.path,
					icon: nil
				)
			}
			tree.onActivate =
			{
				item, retained in activated.append(((item as! Item).path, retained))
			}
			tree.onContextMenu =
			{
				item in
				menuTarget = (item as? Item)?.path
				return NSMenu()
			}
			tree.reloadTree()
			window.layoutIfNeeded()
			#expect(tree.numberOfRows == 1)
			let cell = try #require(tree.view(
				atColumn: 0,
				row: 0,
				makeIfNecessary: true
			) as? ViewerFileTreeRow)
			let chevron = try #require(cell.subviews.compactMap
			{
				$0 as? NSButton
			}.first)
			#expect(chevron.dispatchConfiguredAction())
			#expect(tree.numberOfRows == 2)
			tree.selectRowIndexes(
				IndexSet(integer: 0),
				byExtendingSelection: false
			)
			try sendKey(
				124,
				to: tree,
				in: window
			)
			#expect(tree.selectedItem === file)
			try sendKey(
				36,
				to: tree,
				in: window
			)
			try sendKey(
				49,
				to: tree,
				in: window
			)
			#expect(activated.map(\.0) == [file.path, file.path])
			#expect(activated.map(\.1) == [false, true])
			try sendKey(
				123,
				to: tree,
				in: window
			)
			#expect(tree.selectedItem === folder)
			try sendKey(
				123,
				to: tree,
				in: window
			)
			#expect(tree.numberOfRows == 1)
			#expect(activated.count == 2)
			tree.expandItem(folder)
			let rect = tree.rect(ofRow: 1)
			let point = tree.convert(
				NSPoint(
					x: rect.midX,
					y: rect.midY
				),
				to: nil
			)
			let event = try #require(NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: point,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			))
			#expect(tree.menu(for: event) != nil)
			#expect(menuTarget == file.path)
			#expect(tree.selectedItem === folder)
		}
	}

	private func sendKey(
		_ code: UInt16,
		to tree: ViewerFileTreeView,
		in window: NSWindow
	) throws
	{
		let event = try #require(NSEvent.keyEvent(
			with: .keyDown,
			location: .zero,
			modifierFlags: [],
			timestamp: 0,
			windowNumber: window.windowNumber,
			context: nil,
			characters: "",
			charactersIgnoringModifiers: "",
			isARepeat: false,
			keyCode: code
		))
		tree.keyDown(with: event)
	}
}
