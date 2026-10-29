import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct DesktopTooltipOwnershipTests
{
	@Test func customToolbarViewsKeepTheirActionTooltipsWithoutAnItemTooltip() async throws
	{
		try await AppKitTestIsolation.perform
		{
			let suite = "TooltipOwnership.\(UUID())"
			let defaults = try #require(UserDefaults(suiteName: suite))
			defer
			{
				defaults.removePersistentDomain(forName: suite)
			}
			let fixture = WorkspaceTestFixture(storage: LocalStorage(defaults: defaults))
			let controller = MainWindowController(
				store: fixture.store,
				onOpenProject:
				{
				},
				onInsertPath:
				{
				}
			)
			let window = try #require(controller.window)
			defer
			{
				window.close()
			}
			let toolbar = try #require(window.toolbar)
			var customItems = 0
			var nativeItems = 0
			for identifier in controller.toolbarAllowedItemIdentifiers(toolbar)
				where identifier != .flexibleSpace
			{
				let item = try #require(controller.toolbar(
					toolbar,
					itemForItemIdentifier: identifier,
					willBeInsertedIntoToolbar: false
				))
				if item.view != nil
				{
					customItems += 1
					#expect(
						item.toolTip == nil,
						"Duplicate native tooltip on \(identifier.rawValue)"
					)
				}
				else if !item.label.isEmpty
				{
					nativeItems += 1
					#expect(item.toolTip == item.label)
				}
			}
			#expect(customItems > 0 && nativeItems > 0)
			#expect(controller.toolsToolbar.openButton.toolTip == "New tab")
			#expect(controller.toolsToolbar.openButton.tooltipShortcut == "⇧⌘B")
			#expect(controller.summaryToggleButton.toolTip == "Toggle pinned summary")
			for query in ["needle", ""]
			{
				controller.navigation.searchField.stringValue = query
				controller.navigation.filterThreads()
				#expect(controller.navigation.searchButton.toolTip == "Search")
				#expect(controller.navigation.searchButton.tooltipShortcut == "⌘K")
			}
		}
	}

	@Test func projectPathTooltipDoesNotCoverItsActionButtonsWhenTheCellIsReused() throws
	{
		let cell = ProjectSidebarCellView(frame: .zero)
		for (name, pinned) in [("First", false), ("Second", true)]
		{
			let project = URL(fileURLWithPath: "/tmp/\(name)")
			cell.render(
				project: project,
				name: name,
				isCurrent: true,
				isPinned: pinned,
				canStartChat: true
			)
			#expect(cell.toolTip == nil)
			#expect(cell.textField?.toolTip == nil)
			let actions = descendants(cell).compactMap
			{
				$0 as? SidebarIconButton
			}
			#expect(actions.count == 2)
			#expect(actions.allSatisfy
			{
				$0.toolTip == nil
			})
			#expect(actions.contains
			{
				$0.accessibilityLabel() == "Project actions for \(name)"
			})
		}
	}

	@Test func embeddedSearchContentLeavesTooltipPresentationToItsActionHost() throws
	{
		let result = FileViewerSearchResult(
			location: FileLocation(
				root: "/tmp",
				relativePath: "Sources/Main.swift"
			),
			lineNumber: 7,
			lineText: "let answer = 42"
		)
		for presentation in [
			DesktopSearchResultContentView.Presentation
				.chat(
					title: "Chat",
					context: "Project",
					shortcut: ""
				),
			.content(
				result: result,
				query: "answer"
			)
		]
		{
			let standalone = DesktopSearchResultContentView(presentation: presentation)
			let expected = try #require(standalone.toolTip)
			let button = DesktopSearchResultButton(
				presentation: .content(presentation),
				target: nil,
				action: nil
			)
			#expect(button.toolTip == expected)
			#expect(descendants(button).allSatisfy
			{
				$0.toolTip == nil
			})
			#expect(standalone.toolTip == expected)
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		view.subviews.flatMap
		{
			[$0] + descendants($0)
		}
	}
}
