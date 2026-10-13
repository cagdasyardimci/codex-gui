import AppKit
import Testing

@testable import CodexGUI

@Suite(.serialized) @MainActor
struct NavigationSidebarLayoutTests
{
	@Test func sidebarSpacingCompensatesSectionRowsWithoutChangingTitleAlignment()
	{
		let metrics = LayoutTokens.Sidebar(rowSpacing: 2)
		#expect(NavigationSidebarLayout.isValid(metrics))
		#expect(NavigationSidebarLayout.sectionRowHeight(
			at: 0,
			metrics: metrics
		) == 32)
		#expect(NavigationSidebarLayout.sectionRowHeight(
			at: 3,
			metrics: metrics
		) == 46)
		#expect(metrics.projectTitleInset == 32)
		#expect(LayoutTokens.Sidebar(iconSize: 24).projectTitleInset == 40)
		#expect(!NavigationSidebarLayout.isValid(LayoutTokens.Sidebar(rowSpacing: 5)))
		#expect(!NavigationSidebarLayout.isValid(LayoutTokens.Sidebar(rowHeight: 20)))
	}

	@Test func sectionPaddingPreservesSelectionAndTitleAlignmentAcrossReloads() throws
	{
		_ = NSApplication.shared
		let controller = NavigationViewController()
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 280,
				height: 500
			),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.isReleasedWhenClosed = false
		window.contentViewController = controller
		defer
		{
			window.contentViewController = nil
			window.close()
		}
		let pinned = try task("pinned")
		let child = try task("child")
		controller.currentProject = URL(fileURLWithPath: "/tmp/sidebar-spacing")
		controller.threads = [child]
		controller.selectedThreadID = child.id

		for appearance: NSAppearance.Name in [.aqua, .darkAqua]
		{
			window.appearance = NSAppearance(named: appearance)
			for width: CGFloat in [280, 210]
			{
				window.setContentSize(NSSize(
					width: width,
					height: 500
				))
				controller.pinnedTasks = [pinned]
				controller.filterThreads()
				controller.view.layoutSubtreeIfNeeded()
				let table = controller.chatsTable
				let pinnedHeader = try headerFrame(
					controller,
					row: 0
				)
				let projectsHeader = try headerFrame(
					controller,
					row: 2
				)
				let pinFrame = try cellFrame(
					controller,
					row: 1
				)
				let projectFrame = try cellFrame(
					controller,
					row: 3
				)
				#expect(abs(pinnedHeader.minY - table.rect(ofRow: 0).minY) < 0.01)
				#expect(abs(pinFrame.minY - pinnedHeader.maxY - 4) < 0.01)
				#expect(abs(projectsHeader.minY - pinFrame.maxY - 16) < 0.01)
				#expect(abs(projectFrame.minY - projectsHeader.maxY - 4) < 0.01)
				#expect(pinFrame.height == 30)
				#expect(projectFrame.height == 30)
				#expect(table.selectedRow == 4)
				#expect(!controller.tableView(
					table,
					shouldSelectRow: 0
				))
				#expect(!controller.tableView(
					table,
					shouldSelectRow: 2
				))

				let pinCell = try cell(
					controller,
					row: 1
				)
				let projectCell = try cell(
					controller,
					row: 3
				)
				let childCell = try cell(
					controller,
					row: 4
				)
				#expect(abs(try titleLeading(
					pinCell,
					in: controller.view
				) - 16) < 0.01)
				#expect(abs(try titleLeading(
					projectCell,
					in: controller.view
				) - 40) < 0.01)
				#expect(abs(try titleLeading(
					childCell,
					in: controller.view
				) - 40) < 0.01)

				controller.pinnedTasks = []
				controller.filterThreads()
				controller.view.layoutSubtreeIfNeeded()
				#expect(table.numberOfRows == 2)
				#expect(table.selectedRow == 1)
				let firstProject = try cellFrame(
					controller,
					row: 0
				)
				let firstChild = try cellFrame(
					controller,
					row: 1
				)
				#expect(firstProject.height == 30)
				#expect(firstChild.minY - firstProject.maxY == 1)
				let standaloneHeader = try #require(controller.projectsHeader)
				let standaloneFrame = table.convert(
					standaloneHeader.bounds,
					from: standaloneHeader
				)
				#expect(standaloneFrame.height == 30)
				#expect(abs(firstProject.minY - standaloneFrame.maxY - 4) < 0.01)
				#expect(abs(try titleLeading(
					cell(
						controller,
						row: 1
					),
					in: controller.view
				)
					- 40) < 0.01)
			}
		}

		controller.pinnedTasks = []
		controller.threads = try (0 ..< 6).map
		{
			try task("child-\($0)")
		}
		controller.filterThreads()
		controller.view.layoutSubtreeIfNeeded()
		let childTitle = try titleLeading(
			cell(
				controller,
				row: 5
			),
			in: controller.view
		)
		let showMoreCell = try cell(
			controller,
			row: 6
		)
		#expect(showMoreCell.textField?.stringValue == "Show more")
		#expect(abs(try titleLeading(
			showMoreCell,
			in: controller.view
		) - childTitle) < 0.01)
	}

	private func task(_ id: String) throws -> ThreadSummary
	{
		try #require(ThreadSummary(json: [
			"id": id,
			"name": id,
			"cwd": "/tmp/sidebar-spacing",
		]))
	}

	private func cell(
		_ controller: NavigationViewController,
		row: Int
	) throws -> NSTableCellView
	{
		try #require(controller.chatsTable.view(
			atColumn: 0,
			row: row,
			makeIfNecessary: true
		) as? NSTableCellView)
	}

	private func headerFrame(
		_ controller: NavigationViewController,
		row: Int
	) throws -> NSRect
	{
		let cell = try cell(
			controller,
			row: row
		)
		let header = try #require(cell.subviews.first as? NSStackView)
		cell.layoutSubtreeIfNeeded()
		return controller.chatsTable.convert(
			header.bounds,
			from: header
		)
	}

	private func cellFrame(
		_ controller: NavigationViewController,
		row: Int
	) throws -> NSRect
	{
		let cell = try cell(
			controller,
			row: row
		)
		cell.layoutSubtreeIfNeeded()
		return controller.chatsTable.convert(
			cell.bounds,
			from: cell
		)
	}

	private func titleLeading(
		_ cell: NSTableCellView,
		in view: NSView
	) throws -> CGFloat
	{
		cell.layoutSubtreeIfNeeded()
		let text = try #require(cell.textField)
		return view.convert(
			text.alignmentRect(forFrame: text.frame),
			from: cell
		).minX
	}
}
