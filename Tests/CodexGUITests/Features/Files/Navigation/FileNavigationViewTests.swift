import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct FileNavigationViewTests
{

	@Test func breadcrumbKeepsFullPathAccessibleAndNavigatesRoot() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			let breadcrumb = FileBreadcrumbView(frame: NSRect(
				x: 0,
				y: 0,
				width: 180,
				height: 28
			))
			let location = FileLocation(
				root: "/tmp/workspace",
				relativePath:
				"deep/nested/folder/very-long-file-name.swift"
			)
			var navigated: FileLocation?
			breadcrumb.onNavigate =
			{
				navigated = $0
			}
			breadcrumb.render(
				location: location,
				state: FileViewerState()
			)
			let buttons = breadcrumb.allSubviews().compactMap
			{
				$0 as? NSButton
			}
			#expect(buttons.map(\.title).contains("very-long-file-name.swift"))
			#expect(buttons.first?.toolTip == "/tmp/workspace")
			let rootButton = try #require(buttons.first)
			#expect(rootButton.dispatchConfiguredAction())
			#expect(navigated == FileLocation(
				root: "/tmp/workspace",
				relativePath: ""
			))
		}
	}

	@Test func lazyFolderResultAndFilterPreserveTreeContext() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let root = "/tmp/file-navigation-lazy"
			let base = FileLocation(
				root: root,
				relativePath: ""
			)
			let folder = FileLocation(
				root: root,
				relativePath: "Sources"
			)
			let child = FileLocation(
				root: root,
				relativePath: "Sources/child.swift"
			)
			let unloaded = FileLocation(
				root: root,
				relativePath: "unloaded/deep/child.swift"
			)
			let controller = FileNavigatorViewController()
			let window = NSWindow(contentViewController: controller)
			window.prepareForTesting()
			window.setContentSize(NSSize(
				width: 300,
				height: 400
			))
			defer
			{
				window.close()
			}
			var requested: [FileLocation] = []
			var filters: [String] = []
			controller.onRequestDirectory =
			{
				requested.append($0)
			}
			controller.onFilter =
			{
				filters.append($0)
			}
			var state = FileViewerState()
			state.activeRoot = root
			state.directoryEntries[base] = [FileViewerDirectoryEntry(
				location: folder,
				isDirectory: true,
				isSymbolicLink: false
			)]
			controller.render(state)
			let outline = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSOutlineView
			}.first)
			let folderItem = try #require(outline.item(atRow: 0))
			outline.selectRowIndexes(
				IndexSet(integer: 0),
				byExtendingSelection: false
			)
			await withCheckedContinuation
			{
				continuation in
				controller.onRequestDirectory =
				{
					requested.append($0)
					continuation.resume()
				}
				outline.expandItem(folderItem)
				#expect(requested.isEmpty)
			}
			controller.onRequestDirectory =
			{
				requested.append($0)
			}
			#expect(requested == [folder])
			state.directoryRequests[folder] = UUID()
			controller.render(state)
			#expect(outline.numberOfRows == 2)
			#expect(outline.isItemExpanded(folderItem))
			#expect(outlineLabel(
				outline,
				row: 1
			) == "Loading…")
			state.directoryRequests[folder] = nil
			state.directoryEntries[folder] = [FileViewerDirectoryEntry(
				location: child,
				isDirectory: false,
				isSymbolicLink: false
			)]
			controller.render(state)
			#expect(outline.numberOfRows == 2)
			#expect(outline.isItemExpanded(folderItem))
			#expect(outline.selectedRow == 0)
			#expect(outlineLabel(
				outline,
				row: 1
			) == "child.swift")

			let field = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSSearchField
			}.first)
			window.layoutIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			let searchCell = try #require(field.cell as? NSSearchFieldCell)
			let textRect = searchCell.searchTextRect(forBounds: field.bounds)
			let iconRect = searchCell.searchButtonRect(forBounds: field.bounds)
			#expect(abs(textRect.midY - field.bounds.midY) < 0.5)
			#expect(abs(iconRect.midY - textRect.midY) < 0.5)
			#expect(field.bounds.contains(textRect))
			window.makeKeyAndOrderFront(nil)
			#expect(window.makeFirstResponder(field))
			let editor = try #require(field.currentEditor())
			let editorFrame = editor.convert(
				editor.bounds,
				to: field
			)
			#expect(abs(editorFrame.midY - textRect.midY) < 1)
			field.stringValue = "child"
			controller.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			state.filenameResults = FileViewerSearchPage(
				results: [child, unloaded],
				isTruncated: false
			)
			controller.render(state)
			#expect(filters.last == "child")
			#expect(outline.numberOfRows == 2)
			#expect(outlineLabel(
				outline,
				row: 1
			) == "unloaded/deep/child.swift")
			field.stringValue = ""
			controller.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			controller.render(state)
			#expect(outline.isItemExpanded(folderItem))
			#expect(outline.selectedRow == 0)
			#expect(outlineLabel(
				outline,
				row: 1
			) == "child.swift")
		}
	}

	@Test(
		.timeLimit(.minutes(1)),
		arguments: [false, true]
	)
	func queuedExpansionDoesNotRequestAReplacedWorkspace(changeRoot: Bool) async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let controller = FileNavigatorViewController()
			let window = NSWindow(contentViewController: controller)
			window.prepareForTesting()
			defer
			{
				controller.onRequestDirectory = nil
				window.close()
			}
			var state = FileViewerState()
			state.activeRoot = "/tmp/file-navigation-old-workspace"
			let oldFolder = FileLocation(
				root: state.activeRoot!,
				relativePath: "Sources"
			)
			state.directoryEntries[FileLocation(
				root: state.activeRoot!,
				relativePath: ""
			)] = [
				FileViewerDirectoryEntry(
					location: oldFolder,
					isDirectory: true,
					isSymbolicLink: false
				),
			]
			controller.render(state)
			let outline = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSOutlineView
			}.first)
			let oldItem = try #require(outline.item(atRow: 0))
			outline.expandItem(oldItem)
			outline.collapseItem(oldItem)
			state.generation += 1
			if changeRoot
			{
				state.activeRoot = "/tmp/file-navigation-new-workspace"
			}
			let newFolder = FileLocation(
				root: state.activeRoot!,
				relativePath: "Sources"
			)
			state.directoryEntries[FileLocation(
				root: state.activeRoot!,
				relativePath: ""
			)] = [
				FileViewerDirectoryEntry(
					location: newFolder,
					isDirectory: true,
					isSymbolicLink: false
				),
			]
			controller.render(state)
			let newItem = try #require(outline.item(atRow: 0))
			var requested: [FileLocation] = []
			await withCheckedContinuation
			{
				continuation in
				controller.onRequestDirectory =
				{
					location in
					requested.append(location)
					continuation.resume()
				}
				outline.expandItem(newItem)
			}
			#expect(requested == [newFolder])
		}
	}

	@Test func contentSearchKeepsKeyboardSelectionAndRestoresFocusOnEscape() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let parent = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 700,
					height: 500
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			parent.prepareForTesting()
			let origin = NSTextView(frame: NSRect(
				x: 8,
				y: 8,
				width: 100,
				height: 30
			))
			parent.contentView?.addSubview(origin)
			#expect(parent.makeFirstResponder(origin))
			let panel = FileSearchPanel(mode: .content)
			defer
			{
				panel.dismiss(); parent.close()
			}
			var chosen: FileViewerSearchResult?
			panel.onChooseContent =
			{
				chosen = $0
			}
			var canceled = 0
			panel.onCancelSearch =
			{
				canceled += 1
			}
			var state = FileViewerState()
			state.activeRoot = "/tmp/search-fixture"
			panel.render(state)
			panel.present(in: parent)
			let sheet = try #require(parent.attachedSheet)
			let field = try #require(panel.view.allSubviews().compactMap
			{
				$0 as? NSTextField
			}.first
			{
				$0.accessibilityLabel() == "Search file contents"
			})
			field.stringValue = "needle"
			panel.controlTextDidChange(Notification(
				name: NSControl.textDidChangeNotification,
				object: field
			))
			let status = try #require(panel.view.allSubviews().compactMap
			{
				$0 as? NSTextField
			}.first
			{
				$0.accessibilityLabel() == "Search status"
			})
			state.searchRequest = UUID()
			panel.render(state)
			#expect(status.stringValue == "Searching…")
			state.searchRequest = nil
			state.searchFailure = .unavailable
			panel.render(state)
			#expect(status.stringValue.contains("Search failed"))
			state.searchFailure = nil
			state.contentResults = FileViewerSearchPage(
				results: [],
				isTruncated: false
			)
			panel.render(state)
			#expect(status.stringValue == "No matching content")
			let first = FileViewerSearchResult(
				location: FileLocation(
					root: state.activeRoot!,
					relativePath: "a.txt"
				),
				lineNumber: 2,
				lineText: "needle one"
			)
			let last = FileViewerSearchResult(
				location: FileLocation(
					root: state.activeRoot!,
					relativePath: "deep/a.txt"
				),
				lineNumber: 42,
				lineText: "needle two"
			)
			state.contentResults = FileViewerSearchPage(
				results: [first, last],
				isTruncated: true,
				excludedDirectoryCount: 2
			)
			panel.render(state)
			let table = try #require(panel.view.allSubviews().compactMap
			{
				$0 as? FileSearchResultsTableView
			}.first)
			#expect(table.selectedRow == 0)
			#expect(status.stringValue.contains("Showing first 2 matching lines"))
			#expect(status.toolTip == "2 generated folders skipped")
			try sendKey(
				119,
				to: table,
				in: sheet
			)
			#expect(table.selectedRow == 1)
			let focused = sheet.firstResponder
			let geometry = sheet.frame.size
			for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
			{
				parent.appearance = NSAppearance(named: appearance)
				#expect(sheet.appearance?.name == appearance)
				#expect(sheet.firstResponder === focused)
				#expect(sheet.frame.size == geometry)
				#expect(table.selectedRow == 1)
			}
			panel.render(state)
			#expect(table.selectedRow == 1)
			try sendKey(
				36,
				to: table,
				in: sheet
			)
			#expect(chosen == last)
			#expect(parent.attachedSheet == nil)
			#expect(!sheet.isVisible)
			#expect(canceled == 1)
			#expect(parent.firstResponder === origin)

			panel.present(in: parent)
			let replacement = try #require(parent.attachedSheet)
			try sendKey(
				53,
				to: try #require(panel.view.allSubviews().compactMap
				{
					$0 as? FileSearchResultsTableView
				}.first),
				in: replacement
			)
			#expect(parent.attachedSheet == nil)
			#expect(!replacement.isVisible)
			#expect(canceled == 2)
		}
	}

	private func sendKey(
		_ code: UInt16,
		to table: NSTableView,
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
		table.keyDown(with: event)
	}

	private func outlineLabel(
		_ outline: NSOutlineView,
		row: Int
	) -> String?
	{
		guard row >= 0, row < outline.numberOfRows
		else
		{
			return nil
		}
		return outline.view(
			atColumn: 0,
			row: row,
			makeIfNecessary: true
		)?.accessibilityLabel()
	}
}

@MainActor
private extension NSView
{
	func allSubviews() -> [NSView]
	{
		[subviews,
			subviews.flatMap
			{
			$0.allSubviews()
			}].flatMap
		{
			$0
		}
	}
}
