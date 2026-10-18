import AppKit
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ViewerFileTreeIntegrationTests
{
	@Test func actualNavigatorsShareRowsAndDisclosureBehavior() async throws
	{
		try await AppKitTestIsolation.perform
		{
			@MainActor in
			_ = NSApplication.shared
			let root = "/fixture/SharedTree"
			let filename = "a-very-long-file-name-with-a-distinct-ending.swift"
			let folder = FileLocation(
				root: root,
				relativePath: "Sources"
			)
			let nested = FileLocation(
				root: root,
				relativePath: "Sources/\(filename)"
			)
			let rootLocation = FileLocation(
				root: root,
				relativePath: ""
			)
			let files = FileNavigatorViewController()
			let filesWindow = NSWindow(contentViewController: files)
			filesWindow.isReleasedWhenClosed = false
			filesWindow.setContentSize(NSSize(
				width: 240,
				height: 400
			))
			var opened: [FileLocation] = []
			files.onOpenFile =
			{
				location, _ in opened.append(location)
			}
			var fileState = FileViewerState()
			fileState.activeRoot = root
			fileState.directoryEntries[rootLocation] = [FileViewerDirectoryEntry(
				location: folder,
				isDirectory: true,
				isSymbolicLink: false
			)]
			fileState.directoryEntries[folder] = [FileViewerDirectoryEntry(
				location: nested,
				isDirectory: false,
				isSymbolicLink: false
			)]
			files.render(fileState)

			let model = WorkspaceModel(identity: WorkspaceIdentity(
				sessionID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
				canonicalCheckoutPath: root
			))
			let owner = FeaturePresentationOwner(
				WorkspaceSelectors.snapshot(
					model: model,
					now: .distantPast
				),
				storeIdentity: "shared-tree-fixture"
			)
			let git = GitChangesViewController(runtime: GitReviewRuntime(
				service: SharedTreeFixtureService(path: nested.relativePath)
			))
			let gitWindow = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 900,
					height: 640
				),
				styleMask: [.borderless],
				backing: .buffered,
				defer: false
			)
			gitWindow.isReleasedWhenClosed = false
			gitWindow.contentViewController = git
			defer
			{
				git.close()
				gitWindow.close()
				filesWindow.close()
			}
			git.activate(owner: owner)
			await git.runtime.readTask?.value
			_ = try #require(git.runtime.state.snapshot)
			let selectedFileID = git.runtime.state.selectedFileID
			if git.runtime.state.expandedDirectories.contains(Data("Sources".utf8))
			{
				git.runtime.toggleDirectory("Sources")
			}

			let outline = try #require(descendants(files.view).compactMap
			{
				$0 as? NSOutlineView
			}.first)
			let table = try #require(descendants(git.view).compactMap
			{
				$0 as? NSTableView
			}.first
			{
				$0.accessibilityLabel() == "Changed-file tree"
			})
			#expect(outline.rowHeight == table.rowHeight)
			#expect(outline.backgroundColor == table.backgroundColor)
			#expect(outline.style == table.style)
			#expect(!outline.usesAlternatingRowBackgroundColors)
			#expect(outline.headerView == nil)
			#expect(table.headerView == nil)
			#expect(outline.numberOfRows == 1)
			#expect(table.numberOfRows == 1)
			for appearance: NSAppearance.Name in [.aqua, .darkAqua]
			{
				filesWindow.appearance = NSAppearance(named: appearance)
				gitWindow.appearance = NSAppearance(named: appearance)
				filesWindow.layoutIfNeeded()
				gitWindow.layoutIfNeeded()
				try compareRow(
					try cell(
						outline,
						row: 0
					),
					try cell(
						table,
						row: 0
					)
				)
				let filesRow = try #require(outline.rowView(
					atRow: 0,
					makeIfNecessary: true
				))
				let gitRow = try #require(table.rowView(
					atRow: 0,
					makeIfNecessary: true
				))
				outline.selectRowIndexes(
					IndexSet(integer: 0),
					byExtendingSelection: false
				)
				table.selectRowIndexes(
					IndexSet(integer: 0),
					byExtendingSelection: false
				)
				#expect(filesRow.interiorBackgroundStyle == .normal)
				#expect(gitRow.interiorBackgroundStyle == .normal)
			}

			let fileButton = try disclosure(in: cell(
				outline,
				row: 0
			))
			let gitButton = try disclosure(in: cell(
				table,
				row: 0
			))
			#expect(fileButton.dispatchConfiguredAction())
			#expect(gitButton.dispatchConfiguredAction())
			#expect(outline.numberOfRows == 2)
			#expect(table.numberOfRows == 2)
			#expect(opened.isEmpty)
			#expect(git.runtime.state.selectedFileID == selectedFileID)
			let rowRect = table.rect(ofRow: 1)
			let point = table.convert(
				NSPoint(
					x: rowRect.midX,
					y: rowRect.midY
				),
				to: nil
			)
			let event = try #require(NSEvent.mouseEvent(
				with: .rightMouseDown,
				location: point,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: gitWindow.windowNumber,
				context: nil,
				eventNumber: 1,
				clickCount: 1,
				pressure: 1
			))
			let menu = try #require(table.menu(for: event))
			let copyPath = try #require(menu.item(withTitle: "Copy path"))
			#expect(NSApp.sendAction(
				try #require(copyPath.action),
				to: copyPath.target,
				from: copyPath
			))
			#expect(NSPasteboard.general.string(forType: .string) == nested.fileURL.path)
			#expect(git.runtime.state.selectedFileID == selectedFileID)

			filesWindow.layoutIfNeeded()
			gitWindow.layoutIfNeeded()
			try compareRow(
				try cell(
					outline,
					row: 1
				),
				try cell(
					table,
					row: 1
				)
			)
		}
	}

	private func compareRow(
		_ files: ViewerFileTreeRow,
		_ git: ViewerFileTreeRow
	) throws
	{
		files.layoutSubtreeIfNeeded()
		git.layoutSubtreeIfNeeded()
		#expect(files.nameLabel.font == git.nameLabel.font)
		#expect(files.nameLabel.lineBreakMode == git.nameLabel.lineBreakMode)
		#expect(abs(files.nameLabel.frame.minX - git.nameLabel.frame.minX) < 0.5)
		#expect(abs(files.iconView.frame.minX - git.iconView.frame.minX) < 0.5)
		#expect(abs(files.iconView.frame.maxX - git.iconView.frame.maxX) < 0.5)
		#expect(files.nameLabel.frame.maxX <= files.bounds.maxX)
		#expect(git.nameLabel.frame.maxX <= git.bounds.maxX)
		#expect(files.nameLabel.stringValue == git.nameLabel.stringValue)
	}

	private func cell(
		_ table: NSTableView,
		row: Int
	) throws -> ViewerFileTreeRow
	{
		try #require(table.view(
			atColumn: 0,
			row: row,
			makeIfNecessary: true
		)
			as? ViewerFileTreeRow)
	}

	private func disclosure(in cell: ViewerFileTreeRow) throws -> NSButton
	{
		try #require(cell.subviews.compactMap
		{
			$0 as? NSButton
		}.first)
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap
		{
			descendants($0)
		}
	}
}

private struct SharedTreeFixtureService: GitComparisonService
{
	let path: String

	func compare(_ request: GitComparisonRequest) async -> GitComparisonResult
	{
		let patch = "@@ -1 +1 @@\n-before\n+after\n"
		return .snapshot(GitComparisonSnapshot(
			request: request,
			id: "shared-tree-fixture",
			resolvedBase: "HEAD",
			resolvedTarget: "Working tree",
			patch: Data(patch.utf8),
			files: [GitComparisonFile(
				oldPath: path,
				newPath: path,
				kind: .modified,
				additions: 1,
				deletions: 1,
				isBinary: false,
				patch: patch,
				hunks: [GitComparisonHunk(
					header: "@@ -1 +1 @@",
					text: patch,
					oldStart: 1,
					newStart: 1
				)]
			)]
		))
	}
}
