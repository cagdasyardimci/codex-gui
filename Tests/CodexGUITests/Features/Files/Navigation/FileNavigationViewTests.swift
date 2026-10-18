import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct FileNavigationViewTests
{
	@Test func treeShowsNestedAndHiddenEntriesWithoutOpeningFolders() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let root = "/tmp/file-navigation-fixture"
			let rootLocation = FileLocation(
				root: root,
				relativePath: ""
			)
			let folder = FileLocation(
				root: root,
				relativePath: "Sources"
			)
			let hidden = FileLocation(
				root: root,
				relativePath: ".config"
			)
			let nested = FileLocation(
				root: root,
				relativePath: "Sources/main.swift"
			)
			let duplicate = FileLocation(
				root: root,
				relativePath: "main.swift"
			)
			let controller = FileNavigatorViewController()
			let window = NSWindow(contentViewController: controller)
			window.isReleasedWhenClosed = false
			window.setContentSize(NSSize(
				width: 300,
				height: 400
			))
			defer
			{
				window.close()
			}
			var opened: [(FileLocation, Bool)] = []
			controller.onOpenFile =
			{
				opened.append(($0, $1))
			}
			var requested: [FileLocation] = []
			controller.onRequestDirectory =
			{
				requested.append($0)
			}
			var state = FileViewerState()
			state.activeRoot = root
			controller.render(state)
			#expect(requested == [rootLocation])
			state.directoryEntries[rootLocation] = [
				FileViewerDirectoryEntry(
					location: duplicate,
					isDirectory: false,
					isSymbolicLink: false
				),
				FileViewerDirectoryEntry(
					location: hidden,
					isDirectory: false,
					isSymbolicLink: false
				),
				FileViewerDirectoryEntry(
					location: folder,
					isDirectory: true,
					isSymbolicLink: false
				),
			]
			state.directoryEntries[folder] = [FileViewerDirectoryEntry(
				location: nested,
				isDirectory: false,
				isSymbolicLink: false
			)]
			controller.render(state)
			let outline = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSOutlineView
			}.first)
			#expect(outline.numberOfRows == 3)
			let folderItem = try #require(outline.item(atRow: 0))
			let folderCell = try #require(outline.view(
				atColumn: 0,
				row: 0,
				makeIfNecessary: true
			))
			#expect(folderCell.allSubviews().compactMap
			{
				$0 as? NSImageView
			}.allSatisfy
			{
				$0.isHidden || $0.image == nil
			})
			outline.expandItem(folderItem)
			#expect(outline.numberOfRows == 4)
			#expect(opened.isEmpty)
			window.layoutIfNeeded()
			controller.view.layoutSubtreeIfNeeded()
			let rootFileCell = try #require(outline.view(
				atColumn: 0,
				row: 3,
				makeIfNecessary: true
			))
			let nestedCell = try #require(outline.view(
				atColumn: 0,
				row: 1,
				makeIfNecessary: true
			))
			let folderLabel = try #require(folderCell.allSubviews()
				.compactMap
				{
					$0 as? NSTextField
				}.first)
			let fileLabel = try #require(rootFileCell.allSubviews()
				.compactMap
				{
					$0 as? NSTextField
				}.first)
			let nestedLabel = try #require(nestedCell.allSubviews()
				.compactMap
				{
					$0 as? NSTextField
				}.first)
			let fileIcon = try #require(rootFileCell.allSubviews()
				.compactMap
				{
					$0 as? NSImageView
				}.first)
			let folderText = folderLabel.convert(
				folderLabel.bounds,
				to: outline
			)
			let fileText = fileLabel.convert(
				fileLabel.bounds,
				to: outline
			)
			let nestedText = nestedLabel.convert(
				nestedLabel.bounds,
				to: outline
			)
			#expect(abs(folderText.minX - fileText.minX) < 0.5)
			#expect(abs(nestedText.minX - fileText.minX - outline.indentationPerLevel) < 0.5)
			let fileIconFrame = fileIcon.convert(
				fileIcon.bounds,
				to: outline
			)
			#expect(fileIconFrame.maxX <= fileText.minX)
			#expect(rootFileCell.bounds.contains(fileIcon.frame))
			let nestedRow = (0 ..< outline.numberOfRows).first
			{
				outline.view(
					atColumn: 0,
					row: $0,
					makeIfNecessary: true
				)?
					.accessibilityLabel() == "main.swift"
			}
			let row = try #require(nestedRow)
			outline.selectRowIndexes(
				IndexSet(integer: row),
				byExtendingSelection: false
			)
			_ = NSApp.sendAction(
				try #require(outline.action),
				to: outline.target,
				from: outline
			)
			#expect(opened.count == 1)
			#expect(opened.first?.0 == nested)
			#expect(opened.first?.1 == false)
			_ = NSApp.sendAction(
				try #require(outline.doubleAction),
				to: outline.target,
				from: outline
			)
			#expect(opened.last?.0 == nested)
			#expect(opened.last?.1 == true)
			let frame = outline.frame
			for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				#expect(outline.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
					== appearance)
				#expect(outline.frame == frame)
				#expect(outline.selectedRow == row)
				#expect(outlineLabel(
					outline,
					row: row
				) == "main.swift")
			}
			let openedCount = opened.count
			state.activeRoot = nil
			controller.render(state)
			#expect(outline.numberOfRows == 0)
			_ = NSApp.sendAction(
				try #require(outline.action),
				to: outline.target,
				from: outline
			)
			#expect(opened.count == openedCount)
		}
	}

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

	@Test func breadcrumbCanBuildAtZeroSizeBeforeItsFirstLayout() throws
	{
		let breadcrumb = FileBreadcrumbView()
		breadcrumb.render(
			location: nil,
			state: FileViewerState()
		)
		let stack = try #require(breadcrumb.allSubviews().compactMap
		{
			$0 as? NSStackView
		}.first)
		#expect(stack.frame.width >= stack.edgeInsets.left + stack.edgeInsets.right)
		breadcrumb.frame = NSRect(
			x: 0,
			y: 0,
			width: 180,
			height: 34
		)
		breadcrumb.layoutSubtreeIfNeeded()
		#expect(stack.frame.width >= stack.fittingSize.width)
	}

	@Test func replacedBreadcrumbControlsCannotNavigateTheCurrentLocation() throws
	{
		let breadcrumb = FileBreadcrumbView()
		var state = FileViewerState()
		state.activeRoot = "/tmp/old-workspace"
		breadcrumb.render(
			location: FileLocation(
				root: state.activeRoot!,
				relativePath: "old/file.swift"
			),
			state: state
		)
		let previous = breadcrumb.allSubviews().compactMap
		{
			$0 as? NSButton
		}
		var opened: [FileLocation] = []
		var navigated: [FileLocation] = []
		var requested: [FileLocation] = []
		breadcrumb.onOpenFile =
		{
			opened.append($0)
		}
		breadcrumb.onNavigate =
		{
			navigated.append($0)
		}
		breadcrumb.onRequestDirectory =
		{
			requested.append($0)
		}
		state.activeRoot = "/tmp/new-workspace"
		let current = FileLocation(
			root: state.activeRoot!,
			relativePath: "new/other.swift"
		)
		breadcrumb.render(
			location: current,
			state: state
		)
		for button in previous
		{
			#expect(button.dispatchConfiguredAction())
		}
		#expect(opened.isEmpty)
		#expect(navigated.isEmpty)
		#expect(requested.isEmpty)
		let currentFile = try #require(breadcrumb.allSubviews().compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == "other.swift"
		})
		#expect(currentFile.dispatchConfiguredAction())
		#expect(opened == [current])
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
			window.isReleasedWhenClosed = false
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
			state.directoryFailures[folder] = .unavailable
			controller.render(state)
			#expect(outlineLabel(
				outline,
				row: 1
			) == "Couldn’t load folder. Click to retry.")
			state.directoryFailures[folder] = nil
			state.directoryRequests[folder] = UUID()
			controller.render(state)
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
			let restoredFolderItem = try #require(outline.item(atRow: 0))
			#expect(outlineLabel(
				outline,
				row: 0
			) == "Sources")
			#expect(outline.isItemExpanded(restoredFolderItem))
			#expect(outline.selectedRow == 0)
			#expect(outlineLabel(
				outline,
				row: 1
			) == "child.swift")
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func lazyExpansionAllowsSynchronousStatePublicationAfterNativeExpansion() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let root = "/tmp/file-navigation-expansion-publication"
			let base = FileLocation(
				root: root,
				relativePath: ""
			)
			let folder = FileLocation(
				root: root,
				relativePath: "Sources"
			)
			let nested = FileLocation(
				root: root,
				relativePath: "Sources/Nested"
			)
			let child = FileLocation(
				root: root,
				relativePath: "Sources/Nested/child.swift"
			)
			let controller = FileNavigatorViewController()
			let window = NSWindow(contentViewController: controller)
			window.isReleasedWhenClosed = false
			window.setContentSize(NSSize(
				width: 300,
				height: 400
			))
			defer
			{
				controller.onRequestDirectory = nil
				window.close()
			}
			var state = FileViewerState()
			state.activeRoot = root
			state.directoryEntries[base] = [FileViewerDirectoryEntry(
				location: folder,
				isDirectory: true,
				isSymbolicLink: false
			)]
			controller.render(state)
			window.layoutIfNeeded()
			let outline = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSOutlineView
			}.first)
			var requests: [FileLocation] = []
			for (location, result, isDirectory) in [(folder, nested, true), (nested, child, false)]
			{
				let item = try #require(outline.item(atRow: requests.count))
				outline.selectRowIndexes(
					IndexSet(integer: requests.count),
					byExtendingSelection: false
				)
				await withCheckedContinuation
				{
					continuation in
					controller.onRequestDirectory =
					{
						requested in
						requests.append(requested)
						#expect(requested == location)
						#expect(outline.isItemExpanded(item))
						state.directoryRequests[requested] = UUID()
						controller.render(state)
						#expect(outlineLabel(
							outline,
							row: outline.row(forItem: item) + 1
						)
							== "Loading…")
						state.directoryRequests[requested] = nil
						state.directoryEntries[requested] = [FileViewerDirectoryEntry(
							location: result,
							isDirectory: isDirectory,
							isSymbolicLink: false
						)]
						controller.render(state)
						continuation.resume()
					}
					let count = requests.count
					outline.expandItem(item)
					#expect(requests.count == count)
				}
				#expect(outline.isItemExpanded(item))
				#expect(outline.selectedRow == requests.count - 1)
				#expect(outlineLabel(
					outline,
					row: requests.count
				) == result.fileURL
					.lastPathComponent)
				outline.collapseItem(item)
				outline.expandItem(item)
				#expect(requests.count == (isDirectory ? 1 : 2))
			}
			#expect(requests == [folder, nested])
			#expect(outline.numberOfRows == 3)
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
			window.isReleasedWhenClosed = false
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

	@Test func emptyAndFailedFoldersShowRecoveryRows() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let root = "/tmp/file-navigation-errors"
			let base = FileLocation(
				root: root,
				relativePath: ""
			)
			let empty = FileLocation(
				root: root,
				relativePath: "Empty"
			)
			let failed = FileLocation(
				root: root,
				relativePath: "Failed"
			)
			let controller = FileNavigatorViewController()
			let window = NSWindow(contentViewController: controller)
			window.isReleasedWhenClosed = false
			defer
			{
				window.close()
			}
			var requests: [FileLocation] = []
			controller.onRequestDirectory =
			{
				requests.append($0)
			}
			var state = FileViewerState()
			state.activeRoot = root
			state.directoryEntries[base] = [
				FileViewerDirectoryEntry(
					location: empty,
					isDirectory: true,
					isSymbolicLink: false
				),
				FileViewerDirectoryEntry(
					location: failed,
					isDirectory: true,
					isSymbolicLink: false
				),
			]
			state.directoryEntries[empty] = []
			state.directoryFailures[failed] = .unavailable
			controller.render(state)
			let outline = try #require(controller.view.allSubviews().compactMap
			{
				$0 as? NSOutlineView
			}.first)
			outline.expandItem(try #require(outline.item(atRow: 0)))
			#expect(outlineLabel(
				outline,
				row: 1
			) == "Empty folder")
			outline.expandItem(try #require(outline.item(atRow: 2)))
			#expect(outlineLabel(
				outline,
				row: 3
			) == "Couldn’t load folder. Click to retry.")
			outline.selectRowIndexes(
				IndexSet(integer: 3),
				byExtendingSelection: false
			)
			_ = NSApp.sendAction(
				try #require(outline.action),
				to: outline.target,
				from: outline
			)
			#expect(requests == [failed])
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
			parent.isReleasedWhenClosed = false
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
			#expect(table.numberOfRows == 0)
			chosen = nil
			table.onAccept?()
			#expect(chosen == nil)

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
