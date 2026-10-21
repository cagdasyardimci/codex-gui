import AppKit
import CoreText
import Testing

@testable import CodexGUI

@Suite @MainActor
struct ToolsTabFilesIntegrationTests
{
	@Test func emptyControllerIsNotASelectedFilesWorkspace()
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		#expect(tabs.selectedTabID == nil)
		#expect(tabs.filesLandingTabID == nil)
		#expect(!tabs.isFilesSelected)
		#expect(tabs.selectedFileDocumentID == nil)
	}

	@Test func filesVisibilityTracksTabAndPanePresentation() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		var visibility: [Bool] = []
		tabs.onFilesPresentationVisible =
		{
			visibility.append($0)
		}
		#expect(visibility == [false])
		tabs.showFilesLanding(controller())
		#expect(visibility == [false, true])
		tabs.setContentVisible(false)
		#expect(visibility == [false, true, false])
		tabs.setContentVisible(true)
		#expect(visibility == [false, true, false, true])
		tabs.showSources(controller())
		#expect(visibility == [false, true, false, true, false])
	}

	@Test func landingReusesBlankAndDocumentsShareOuterStrip() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		let blank = try #require(tabs.selectedTabID)
		let landing = controller()
		tabs.showFilesLanding(landing)
		#expect(tabs.filesLandingTabID == blank)
		#expect(tabs.tabCount == 1)
		tabs.showFilesLanding(landing)
		#expect(tabs.tabCount == 1)
		let first = FileToolTabPresentation(
			id: UUID(),
			title: "one.swift",
			path: "/work/one.swift",
			isPreview: true,
			isDirty: false
		)
		let second = FileToolTabPresentation(
			id: UUID(),
			title: "one.swift",
			path: "/work/sub/one.swift",
			isPreview: false,
			isDirty: true
		)
		let files = controller()
		tabs.updateFileTabs(
			presentations: [first, second],
			selectedID: second.id,
			controller: files
		)
		#expect(tabs.tabCount == 2)
		#expect(tabs.filesLandingTabID == nil)
		#expect(tabs.selectedFileDocumentID == second.id)
		#expect(files.parent === tabs)
		let previewButton = try #require(button(
			"one.swift 1",
			in: tabs.tabBarView
		))
		let retainedButton = try #require(button(
			"one.swift 2",
			in: tabs.tabBarView
		))
		#expect(NSFontManager.shared.traits(of: try #require(previewButton.font))
			.contains(.italicFontMask))
		#expect(!NSFontManager.shared.traits(of: try #require(retainedButton.font))
			.contains(.italicFontMask))
		#expect(previewButton.font?.familyName == retainedButton.font?.familyName)
		#expect(previewButton.font?.pointSize == retainedButton.font?.pointSize)
		let previewFont = try #require(previewButton.font)
		let retainedFont = try #require(retainedButton.font)
		#expect(CTFontCopyVariation(previewFont as CTFont) as? [NSNumber: NSNumber]
			== CTFontCopyVariation(retainedFont as CTFont) as? [NSNumber: NSNumber])
		#expect(previewButton.image?.isTemplate == true)
		#expect(previewButton.image?.accessibilityDescription == "Swift source")
		tabs.showChanges(controller())
		tabs.showSources(controller())
		tabs.showSubagents(controller())
		#expect(tabs.tabCount == 5)
		#expect(!tabs.isFilesSelected)
		tabs.setExpanded(true)
		try select(
			"Chat: New chat",
			in: tabs.tabBarView
		)
		#expect(tabs.isConversationSelected)
		try select(
			"one.swift 2",
			in: tabs.tabBarView
		)
		#expect(tabs.selectedFileDocumentID == second.id)
	}

	@Test func directoryPublicationsKeepFilesLandingSelectedUntilAFileOpens() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		tabs.openNewTab()
		tabs.showChanges(controller())
		tabs.openNewTab()
		let files = controller()
		tabs.showFilesLanding(files)
		let landingID = try #require(tabs.filesLandingTabID)
		tabs.openNewTab()
		let blankID = try #require(tabs.selectedTabID)
		try select(
			"Files 2",
			in: tabs.tabBarView
		)
		#expect(tabs.selectedTabID == landingID)

		var tabSelectionChanges = 0
		var changesSelectionChanges = 0
		var fileSelections: [UUID] = []
		tabs.onTabSelectionChange =
		{
			tabSelectionChanges += 1
		}
		tabs.onChangesSelectionChange =
		{
			changesSelectionChanges += 1
		}
		tabs.onFileSelected =
		{
			fileSelections.append($0)
		}
		for _ in 0 ..< 2
		{
			tabs.updateFileTabs(
				presentations: [],
				selectedID: nil,
				controller: files
			)
			#expect(tabs.selectedTabID == landingID)
			#expect(tabs.filesLandingTabID == landingID)
			#expect(tabs.isFilesSelected)
			#expect(tabSelectionChanges == 0)
			#expect(changesSelectionChanges == 0)
			#expect(fileSelections.isEmpty)
		}

		let opened = document("opened.swift")
		tabs.updateFileTabs(
			presentations: [opened],
			selectedID: opened.id,
			controller: files
		)
		#expect(tabs.filesLandingTabID == nil)
		#expect(tabs.selectedFileDocumentID == opened.id)
		#expect(tabSelectionChanges == 1)
		#expect(changesSelectionChanges == 1)
		#expect(fileSelections.isEmpty)

		tabs.updateFileTabs(
			presentations: [],
			selectedID: nil,
			controller: files
		)
		#expect(tabs.selectedTabID == blankID)
		#expect(tabSelectionChanges == 2)
		#expect(changesSelectionChanges == 2)
		#expect(fileSelections.isEmpty)

		tabs.showChanges(controller())
		let changesID = try #require(tabs.changesTabID)
		let background = document("background.swift")
		let selectionChangesBeforeBackground = tabSelectionChanges
		let changesChangesBeforeBackground = changesSelectionChanges
		tabs.updateFileTabs(
			presentations: [background],
			selectedID: background.id,
			controller: files
		)
		#expect(tabs.selectedTabID == changesID)
		#expect(tabs.isChangesSelected)
		#expect(tabSelectionChanges == selectionChangesBeforeBackground)
		#expect(changesSelectionChanges == changesChangesBeforeBackground)
		#expect(fileSelections.isEmpty)
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

	@Test func backgroundPublicationKeepsAnotherToolSelectedAndCloseChoosesRightNeighbor() throws
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
		#expect(tabs.selectedFileDocumentID == b.id)
		tabs.updateFileTabs(
			presentations: [a, c],
			selectedID: nil,
			controller: files
		)
		#expect(tabs.selectedFileDocumentID == c.id)
		tabs.showChanges(controller())
		let changes = tabs.selectedTabID
		tabs.updateFileTabs(
			presentations: [a, c],
			selectedID: a.id,
			controller: files
		)
		#expect(tabs.selectedTabID == changes)
		#expect(tabs.isChangesSelected)
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

	@Test func closingReorderedSelectedFileChoosesRightOuterNeighbor() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let a = document("a.swift")
		let b = document("b.swift")
		let c = document("c.swift")
		let files = controller()
		let text = NSTextView()
		text.string = "unchanged source bytes\n"
		files.view = text
		tabs.updateFileTabs(
			presentations: [a, b, c],
			selectedID: b.id,
			controller: files
		)
		let cButton = try #require(button(
			"c.swift 3",
			in: tabs.tabBarView
		))
		let cSurface = try #require(cButton.superview as? ToolsTabSurface)
		cSurface.onDrop?(a.id, false)
		#expect(button(
			"b.swift 1",
			in: tabs.tabBarView
		) != nil)
		var requested: [UUID] = []
		var selected: [UUID] = []
		tabs.onFileCloseRequested =
		{
			requested.append($0)
		}
		tabs.onFileSelected =
		{
			selected.append($0)
		}
		try select(
			"Close tab 1",
			in: tabs.tabBarView
		)
		#expect(requested == [b.id])
		#expect(tabs.selectedFileDocumentID == b.id)
		tabs.updateFileTabs(
			presentations: [a, c],
			selectedID: a.id,
			controller: files
		)
		#expect(tabs.selectedFileDocumentID == c.id)
		#expect(selected == [c.id])
		#expect(files.parent === tabs)
		#expect((files.view as? NSTextView)?.string == "unchanged source bytes\n")
	}

	@Test func closingReorderedLastFileChoosesAdjacentChangesTab() throws
	{
		_ = NSApplication.shared
		let tabs = ToolsTabViewController()
		let a = document("a.swift")
		let b = document("b.swift")
		let files = controller()
		tabs.updateFileTabs(
			presentations: [a, b],
			selectedID: b.id,
			controller: files
		)
		tabs.showChanges(controller())
		let changesID = try #require(tabs.changesTabID)
		let changes = try #require(button(
			"Changes 3",
			in: tabs.tabBarView
		))
		let changesSurface = try #require(changes.superview as? ToolsTabSurface)
		changesSurface.onDrop?(b.id, false)
		try select(
			"b.swift 3",
			in: tabs.tabBarView
		)
		var requested: [UUID] = []
		var selected: [UUID] = []
		tabs.onFileCloseRequested =
		{
			requested.append($0)
		}
		tabs.onFileSelected =
		{
			selected.append($0)
		}
		try select(
			"Close tab 3",
			in: tabs.tabBarView
		)
		#expect(requested == [b.id])
		tabs.updateFileTabs(
			presentations: [a],
			selectedID: a.id,
			controller: files
		)
		#expect(tabs.selectedTabID == changesID)
		#expect(tabs.isChangesSelected)
		#expect(selected.isEmpty)
		#expect(files.parent === tabs)
	}

	@Test func selectedOverflowFileTabIsRevealed() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let tabs = ToolsTabViewController()
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 320,
					height: 80
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
			let host = try #require(window.contentView)
			let header = tabs.tabBarView
			header.translatesAutoresizingMaskIntoConstraints = false
			host.addSubview(header)
			NSLayoutConstraint.activate([
				header.leadingAnchor.constraint(equalTo: host.leadingAnchor),
				header.topAnchor.constraint(equalTo: host.topAnchor),
				header.widthAnchor.constraint(equalToConstant: 308),
				header.heightAnchor.constraint(equalToConstant: 44),
			])
			window.layoutIfNeeded()
			let documents = (0 ..< 5).map
			{
				self.document("file\($0).swift")
			}
			tabs.updateFileTabs(
				presentations: documents,
				selectedID: documents[4].id,
				controller: self.controller()
			)
			header.layoutSubtreeIfNeeded()
			let scroll = try #require(self.scrollView(in: header))
			let last = try #require(self.button(
				"file4.swift 5",
				in: header
			))
			let surface = try #require(last.superview)
			#expect(scroll.documentVisibleRect.contains(surface.frame))
		}
	}

	@Test func inactiveHoverAndRetainedAppearanceKeepTabGeometryAndFocus() async throws
	{
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let tabs = ToolsTabViewController()
			let first = self.document("first.swift")
			let second = FileToolTabPresentation(
				id: UUID(),
				title: "second.swift",
				path: "/work/second.swift",
				isPreview: false,
				isDirty: false
			)
			let window = NSWindow(
				contentRect: NSRect(
					x: 0,
					y: 0,
					width: 580,
					height: 80
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
			let host = try #require(window.contentView)
			let header = tabs.tabBarView
			header.frame = host.bounds
			host.addSubview(header)
			tabs.updateFileTabs(
				presentations: [first, second],
				selectedID: second.id,
				controller: self.controller()
			)
			window.layoutIfNeeded()
			let inactive = try #require(self.button(
				"first.swift 1",
				in: header
			))
			let surface = try #require(inactive.superview as? ToolsTabSurface)
			let close = try #require(self.button(
				"Close tab 1",
				in: header
			))
			let frame = surface.frame
			#expect(close.alphaValue == 0)
			let event = try #require(NSEvent.otherEvent(
				with: .applicationDefined,
				location: .zero,
				modifierFlags: [],
				timestamp: 0,
				windowNumber: window.windowNumber,
				context: nil,
				subtype: 0,
				data1: 0,
				data2: 0
			))
			surface.mouseEntered(with: event)
			#expect(close.alphaValue == 1)
			#expect(surface.frame == frame)
			surface.mouseExited(with: event)
			#expect(close.alphaValue == 0)
			let retained = try #require(self.button(
				"second.swift 2",
				in: header
			))
			#expect(window.makeFirstResponder(retained))
			for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua]
			{
				window.appearance = NSAppearance(named: appearance)
				window.layoutIfNeeded()
				#expect(tabs.selectedFileDocumentID == second.id)
				#expect(self.button(
					"second.swift 2",
					in: header
				) === retained)
				#expect(window.firstResponder === retained)
				#expect(surface.frame == frame)
				if let directory = ProcessInfo.processInfo.environment["CODEX_FILES_QA_DIR"]
				{
					try AppTestPNGWriter.write(
						header,
						to: URL(fileURLWithPath: directory)
							.appendingPathComponent("file-tabs-\(appearance.rawValue).png")
					)
				}
			}
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
