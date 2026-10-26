import AppKit
import XCTest

/// Launched-app UI assertions. Internal state is attached only as diagnostic evidence.
@MainActor
final class StreamingStopWorkflowTests: XCTestCase
{
	private var application: XCUIApplication?
	private var runDirectory: URL?
	private var step = "Launch"
	private var expectation = "QA app launches"
	private var targetIdentifier = ""
	private var checkpointNumber = 0
	private var collectingFailure = false
	private var streamedPrefix = ""
	private var clipboardObservation: [String: Any] = [:]
	private var componentAppearance: String?
	private var clipboardRestoration: (() -> Void)?

	override func setUp() async throws
	{
		continueAfterFailure = false
		executionTimeAllowance = 120
		let path = try XCTUnwrap(ProcessInfo.processInfo.environment["CODEX_GUI_E2E_RUN_DIRECTORY"])
		guard path.hasPrefix("/")
		else
		{
			throw EvidenceError.invalidRunDirectory
		}
		let directory = URL(fileURLWithPath: path)
		runDirectory = directory
		let app = XCUIApplication(url: directory.appendingPathComponent("CodexGUI QA.app"))
		application = app
		app.launchEnvironment = [
			"CODEX_EXECUTABLE": directory.appendingPathComponent("qa-backend").path,
			"CODEX_GUI_QA_STATE": directory.appendingPathComponent("backend-state.json").path,
			"CODEX_GUI_QA_TRACE": directory.appendingPathComponent("backend-trace.jsonl").path,
			"CODEX_GUI_WORKSPACE_ROOT": directory.appendingPathComponent("task-workspaces").path,
			"CODEX_GUI_SUPPORT_ROOT": directory.appendingPathComponent("support").path,
			"CODEX_GUI_PREFERENCES_SUITE": try XCTUnwrap(
				ProcessInfo.processInfo.environment["CODEX_GUI_E2E_PREFERENCES_SUITE"]
			),
			"CODEX_GUI_E2E_STATE": directory.appendingPathComponent("state-history.json").path,
		]
		if name.contains("LightAppearance") || name.contains("DarkAppearance")
		{
			let appearance = name.contains("LightAppearance") ? "Light" : "Dark"
			componentAppearance = appearance
			let isolated = directory.appendingPathComponent("components-" + appearance.lowercased())
			executionTimeAllowance = 240
			app.launchEnvironment["CODEX_GUI_E2E_APPEARANCE"] = appearance
			app.launchEnvironment["CODEX_GUI_QA_STATE"] = isolated
				.appendingPathComponent("backend-state.json").path
			app.launchEnvironment["CODEX_GUI_QA_TRACE"] = isolated
				.appendingPathComponent("backend-trace.jsonl").path
			app.launchEnvironment["CODEX_GUI_E2E_STATE"] = isolated
				.appendingPathComponent("state-history.json").path
			app.launchEnvironment["CODEX_GUI_SUPPORT_ROOT"] = isolated
				.appendingPathComponent("support").path
			app.launchEnvironment["CODEX_GUI_WORKSPACE_ROOT"] = isolated
				.appendingPathComponent("workspaces").path
			app.launchEnvironment["CODEX_GUI_PREFERENCES_SUITE"]! += "." + appearance.lowercased()
		}
		app.launch()

	}

	override func tearDown() async throws
	{
		if (testRun?.totalFailureCount ?? 0) > 0, !collectingFailure
		{
			if componentAppearance != nil
			{
				captureComponent("failure")
			}
			else
			{
				capture(
					"failure-in-teardown",
					issue: "Unexpected XCTest failure; see test results"
				)
			}
		}
		application?.terminate()
		clipboardRestoration?()
		clipboardRestoration = nil
		if let appearance = componentAppearance,
			let suite = ProcessInfo.processInfo.environment["CODEX_GUI_E2E_PREFERENCES_SUITE"]
		{
			UserDefaults(suiteName: suite + "." + appearance.lowercased())?
				.removePersistentDomain(forName: suite + "." + appearance.lowercased())
		}
	}

	func testComponentsInLightAppearance() throws
	{
		try verifyComponents()
	}
	func testComponentsInDarkAppearance() throws
	{
		try verifyComponents()
	}

	private func verifyComponents() throws
	{
		let app = try XCTUnwrap(application)
		let directory = try XCTUnwrap(runDirectory)
		try openComponentProject(
			app,
			directory: directory
		)
		let chat = app.descendants(matching: .any)["conversation-qa-reading"].firstMatch
		require(
			chat,
			predicate: "exists == true AND hittable == true",
			description: "Component fixture is available"
		)
		chat.click()
		let composer = app.textViews["conversation-composer"].firstMatch
		require(
			composer,
			predicate: "exists == true AND hittable == true",
			description: "Composer is ready"
		)
		captureComponent("conversation")
		try verifyAppearance()

		// App-level typing proves dismissal restores focus without clicking the field again.
		composer.click()
		app.buttons["Search conversation titles and previews"].firstMatch.click()
		let search = app.searchFields["Search conversation titles and previews"].firstMatch
		require(
			search,
			predicate: "exists == true",
			description: "Chat search is presented"
		)
		paste(
			"Component",
			into: search,
			focus: false
		)
		require(
			search,
			predicate: "value == 'Component'",
			description: "Chat search receives initial keyboard focus"
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("chat-search-keyboard")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			search,
			predicate: "exists == false",
			description: "Escape dismisses chat search"
		)
		paste(
			"focus-chat",
			into: composer,
			focus: false
		)
		require(
			composer,
			predicate: "value == 'focus-chat'",
			description: "Chat search restores composer focus"
		)
		paste(
			"",
			into: composer
		)

		try verifyNavigationMenus(app)

		let model = app.buttons.matching(NSPredicate(
			format: "label BEGINSWITH %@",
			"Model and effort:"
		)).firstMatch
		require(
			model,
			predicate: "exists == true AND enabled == true",
			description: "Model selector is available"
		)
		model.click()
		let chooseModel = app.buttons["Choose Codex model"].firstMatch
		require(
			chooseModel,
			predicate: "exists == true",
			description: "Model popover is presented"
		)
		chooseModel.click()
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("model-menu-keyboard")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		if chooseModel.exists
		{
			app.typeKey(
				.escape,
				modifierFlags: []
			)
		}
		require(
			chooseModel,
			predicate: "exists == false",
			description: "Escape dismisses nested model popovers"
		)
		paste(
			"focus-model",
			into: composer,
			focus: false
		)
		require(
			composer,
			predicate: "value == 'focus-model'",
			description: "Model popover restores composer focus"
		)
		paste(
			"",
			into: composer
		)

		let permission = app.buttons.matching(NSPredicate(
			format: "label BEGINSWITH %@",
			"Approval policy:"
		)).firstMatch
		permission.click()
		let approval = app.links["Learn more about sandboxing and approvals"].firstMatch
		require(
			approval,
			predicate: "exists == true",
			description: "Approval menu is presented"
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("approval-keyboard")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			approval,
			predicate: "exists == false",
			description: "Escape dismisses approval menu"
		)

		for cancellation in ["escape", "button"]
		{
			permission.click()
			let fullAccess = app.menuItems.matching(NSPredicate(
				format: "label BEGINSWITH %@",
				"Full access"
			)).firstMatch
			require(
				fullAccess,
				predicate: "exists == true AND hittable == true",
				description: "Full-access menu action is available"
			)
			app.typeKey(
				.downArrow,
				modifierFlags: []
			)
			app.typeKey(
				.downArrow,
				modifierFlags: []
			)
			app.typeKey(
				.space,
				modifierFlags: []
			)
			let confirmAccess = app.buttons["Confirm"].firstMatch
			require(
				confirmAccess,
				predicate: "exists == true AND hittable == true",
				description: "Rich full-access dialog is presented"
			)
			captureComponent("full-access-dialog-" + cancellation)
			if cancellation == "escape"
			{
				app.typeKey(
					.escape,
					modifierFlags: []
				)
			}
			else
			{
				app.buttons["Cancel"].firstMatch.click()
			}
			require(
				confirmAccess,
				predicate: "exists == false",
				description: "Rich confirmation cancellation: " + cancellation
			)

		}

		app.typeKey(
			"p",
			modifierFlags: [.command, .shift]
		)
		let commands = app.searchFields.matching(NSPredicate(
			format: "placeholderValue == %@",
			"Find a project, conversation, or action"
		)).firstMatch
		require(
			commands,
			predicate: "exists == true",
			description: "Command palette is presented"
		)
		paste(
			"fixture",
			into: commands,
			focus: false
		)
		require(
			commands,
			predicate: "value == 'fixture'",
			description: "Command sheet owns initial focus"
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("command-sheet")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			commands,
			predicate: "exists == false",
			description: "Escape closes command sheet"
		)

		app.typeKey(
			"f",
			modifierFlags: [.command, .shift]
		)
		let messages = app.searchFields["Search loaded message contents"].firstMatch
		require(
			messages,
			predicate: "exists == true",
			description: "Message search is presented"
		)
		paste(
			"consolidated",
			into: messages,
			focus: false
		)
		require(
			messages,
			predicate: "value == 'consolidated'",
			description: "Message sheet owns initial focus"
		)
		captureComponent("message-sheet")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			messages,
			predicate: "exists == false",
			description: "Escape closes message search"
		)

		// Return, Escape, forward Tab and reverse Tab must all leave the fixture intact.
		for keyPath in ["return", "escape", "tab", "shift-tab"]
		{
			chat.rightClick()
			app.menuItems["Permanently delete"].firstMatch.click()
			let cancel = app.buttons["Cancel"].firstMatch
			require(
				cancel,
				predicate: "exists == true AND hittable == true",
				description: "Delete confirmation is presented"
			)
			captureComponent("delete-" + keyPath)
			switch keyPath
			{
			case "return": app.typeKey(
					.return,
					modifierFlags: []
				)
			case "escape": app.typeKey(
					.escape,
					modifierFlags: []
				)
			case "tab":
				app.typeKey(
					.tab,
					modifierFlags: []
				)
				app.typeKey(
					.tab,
					modifierFlags: []
				)
				app.typeKey(
					.space,
					modifierFlags: []
				)
			default:
				app.typeKey(
					.tab,
					modifierFlags: .shift
				)
				captureComponent("delete-reverse-tab-focused")
				app.typeKey(
					.space,
					modifierFlags: []
				)
			}
			require(
				cancel,
				predicate: "exists == false",
				description: "Keyboard path safely dismisses deletion: " + keyPath
			)
			require(
				chat,
				predicate: "exists == true",
				description: "Keyboard cancellation preserves the chat"
			)
		}

		chat.rightClick()
		app.menuItems["Rename"].firstMatch.click()
		let rename = app.textFields.matching(NSPredicate(
			format: "label IN %@",
			["Task name", "Conversation name"]
		)).firstMatch
		require(
			rename,
			predicate: "exists == true",
			description: "Native rename prompt is presented"
		)
		app.typeKey(
			"a",
			modifierFlags: .command
		)
		paste(
			"FOCUS_RENAME",
			into: rename,
			focus: false
		)
		require(
			rename,
			predicate: "value == 'FOCUS_RENAME'",
			description: "Native prompt owns initial input focus"
		)
		captureComponent("native-rename")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			rename,
			predicate: "exists == false",
			description: "Escape cancels native rename"
		)
		require(
			chat,
			predicate: "exists == true",
			description: "Cancelled rename retains the captured chat"
		)

		let project = app.tables["Projects and saved conversations"]
			.staticTexts["project with spaces"].firstMatch
		project.rightClick()
		app.menuItems["Rename"].firstMatch.click()
		let projectName = app.textFields["Project name"].firstMatch
		require(
			projectName,
			predicate: "exists == true AND hittable == true",
			description: "Project rename form is presented"
		)
		paste(
			"FOCUS_PROJECT",
			into: projectName,
			focus: false
		)
		captureComponent("project-rename")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			projectName,
			predicate: "exists == false",
			description: "Escape cancels project rename"
		)
		require(
			project,
			predicate: "exists == true",
			description: "Cancelled rename preserves the project"
		)
		chat.click()

		let copy = app.buttons["Copy code block 1"].firstMatch
		require(
			copy,
			predicate: "exists == true AND hittable == true",
			description: "Code copy action is available"
		)
		copy.hover()
		let tooltip = app.staticTexts["Copy code"].firstMatch
		require(
			tooltip,
			predicate: "exists == true",
			description: "Shared copy tooltip appears on native hover"
		)
		captureComponent("copy-tooltip")
		try verifyCopy(
			copy,
			expected: "let consolidated = true\nprint(consolidated)\n"
		)

		let expand = app.buttons["Expand Ran printf COMPONENT_TERMINAL"].firstMatch
		require(
			expand,
			predicate: "exists == true",
			description: "Activity disclosure exposes its subject"
		)
		expand.click()
		let output = app.textViews["Shell output"].firstMatch
		require(
			output,
			predicate: "exists == true AND hittable == true",
			description: "Activity expands the shared terminal card"
		)
		let copyOutput = app.buttons["Copy output"].firstMatch
		copyOutput.hover()
		require(
			app.staticTexts["Copy output"].firstMatch,
			predicate: "exists == true",
			description: "Terminal shares the native hover tooltip"
		)
		captureComponent("terminal-expanded")
		try verifyCopy(
			copyOutput,
			expected: "COMPONENT_TERMINAL\n"
		)
		app.buttons["Collapse Ran printf COMPONENT_TERMINAL"].firstMatch.click()
		require(
			output,
			predicate: "exists == false",
			description: "Activity disclosure collapses terminal content"
		)

		try verifyFilesAndImage(app)

		app.menuBars.menuItems["Settings…"].click()
		let settingsSearch = app.searchFields["Search settings"].firstMatch
		require(
			settingsSearch,
			predicate: "exists == true",
			description: "Settings is presented"
		)
		paste(
			"General",
			into: settingsSearch,
			focus: false
		)
		require(
			settingsSearch,
			predicate: "value == 'General'",
			description: "Settings search receives initial focus"
		)
		paste(
			"",
			into: settingsSearch
		)
		let editor = app.buttons["Preferred editor"].firstMatch
		require(
			editor,
			predicate: "exists == true AND hittable == true",
			description: "Shared Settings selector is available"
		)
		editor.click()
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("settings-choice-keyboard")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		app.buttons["Archived chats"].firstMatch.click()
		let archivedDelete = app.buttons["Delete Archived component fixture"].firstMatch
		require(
			archivedDelete,
			predicate: "exists == true AND enabled == true",
			description: "Archived fixture row is available"
		)
		archivedDelete.click()
		captureComponent("archived-delete")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			archivedDelete,
			predicate: "exists == true AND hittable == true",
			description: "Escape preserves archived chat"
		)
		app.buttons["Browser"].firstMatch.click()
		app.buttons["Manage"].firstMatch.click()
		let addSite = app.buttons["Add site"].firstMatch
		require(
			addSite,
			predicate: "exists == true AND enabled == true",
			description: "Browser form can be opened"
		)
		addSite.click()
		let site = app.textFields["Site"].firstMatch
		require(
			site,
			predicate: "exists == true",
			description: "Shared site input is presented"
		)
		paste(
			"not a URL",
			into: site,
			focus: false
		)
		require(
			site,
			predicate: "value == 'not a URL'",
			description: "Form input receives initial focus"
		)
		app.typeKey(
			"a",
			modifierFlags: []
		)
		require(
			site,
			predicate: "value == 'not a URLa'",
			description: "Typing appends to the active site input"
		)
		app.typeKey(
			.delete,
			modifierFlags: []
		)
		require(
			site,
			predicate: "value == 'not a URL'",
			description: "Delete removes the typed character"
		)
		require(
			app.buttons["Add"].firstMatch,
			predicate: "exists == true AND enabled == false",
			description: "Invalid site input disables Add"
		)

		captureComponent("form-invalid")
		paste(
			"https://example.invalid",
			into: site
		)
		let add = app.buttons["Add"].firstMatch
		require(
			add,
			predicate: "exists == true AND enabled == false",
			description: "Unchanged defaults keep Add disabled"
		)
		app.buttons["Browse"].firstMatch.click()
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		app.typeKey(
			.return,
			modifierFlags: []
		)
		require(
			add,
			predicate: "exists == true AND enabled == true",
			description: "Valid input with changed permissions enables Add"
		)
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			site,
			predicate: "exists == false",
			description: "Escape dismisses the form"
		)
		captureComponent("settings-finished")
	}

	private func verifyNavigationMenus(_ app: XCUIApplication) throws
	{
		app.buttons["workspace-status"].firstMatch.click()
		let usage = app.menuItems["Usage"].firstMatch
		require(
			usage,
			predicate: "exists == true AND value == 'Unavailable'",
			description: "Account usage status is accessible"
		)
		let settings = app.menuItems["Settings"].firstMatch
		require(
			settings,
			predicate: "exists == true AND hittable == true",
			description: "Account menu uses shared rows"
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("account-menu")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			settings,
			predicate: "exists == false",
			description: "Escape dismisses the account menu"
		)
		app.staticTexts["Projects"].firstMatch.hover()
		app.buttons["Organize sidebar and sort chats"].firstMatch.click()
		let organize = app.menuItems["Organize sidebar"].firstMatch
		require(
			organize,
			predicate: "exists == true",
			description: "Sidebar menu is presented"
		)
		app.typeKey(
			.rightArrow,
			modifierFlags: []
		)
		let grouped = app.menuItems["By project"].firstMatch
		require(
			grouped,
			predicate: "exists == true",
			description: "Right arrow opens sidebar submenu"
		)
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		captureComponent("sidebar-submenu-keyboard")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		if organize.exists
		{
			app.typeKey(
				.escape,
				modifierFlags: []
			)
		}
		require(
			organize,
			predicate: "exists == false",
			description: "Escape dismisses sidebar menu hierarchy"
		)
	}

	private func verifyFilesAndImage(_ app: XCUIApplication) throws
	{
		app.typeKey(
			"p",
			modifierFlags: .command
		)
		let query = app.textFields["Open file by name"].firstMatch
		require(
			query,
			predicate: "exists == true AND hittable == true",
			description: "Filename search is presented"
		)
		paste(
			"example",
			into: query,
			focus: false
		)
		captureComponent("file-search-keycaps")
		app.typeKey(
			.downArrow,
			modifierFlags: []
		)
		app.typeKey(
			.return,
			modifierFlags: []
		)
		require(
			query,
			predicate: "exists == false",
			description: "Return opens the selected file"
		)
		let file = app.textViews.matching(NSPredicate(
			format: "value CONTAINS %@",
			"Synthetic E2E fixture"
		)).firstMatch
		require(
			file,
			predicate: "exists == true AND hittable == true",
			description: "Shared viewer displays selected file content"
		)
		captureComponent("file-viewer-toolbar")
		let imageChat = app.descendants(matching: .any)["conversation-qa-image"].firstMatch
		imageChat.click()
		let image = app.buttons["Open attached image: activity-preview.png"].firstMatch
		require(
			image,
			predicate: "exists == true AND enabled == true AND hittable == true",
			description: "Attachment tile finishes loading"
		)
		image.click()
		let overlay = app.descendants(matching: .any)["expanded-image-preview"].firstMatch
		require(
			overlay,
			predicate: "exists == true",
			description: "Expanded image controls are presented"
		)
		let zoom = app.descendants(matching: .any)["expanded-image-zoom"].firstMatch
		zoom.click()
		app.menuItems["200%"].firstMatch.click()
		captureComponent("expanded-image-zoom")
		app.typeKey(
			.escape,
			modifierFlags: []
		)
		require(
			overlay,
			predicate: "exists == false",
			description: "Escape dismisses expanded image"
		)
		app.descendants(matching: .any)["conversation-qa-reading"].firstMatch.click()
	}

	private func openComponentProject(
		_ app: XCUIApplication,
		directory: URL
	) throws
	{
		app.menuBars.menuBarItems["File"].click()
		app.menuBars.menuItems["Open Project…"].click()
		let panel = app.dialogs["open-panel"].firstMatch
		require(
			panel,
			predicate: "exists == true",
			description: "Isolated fixture picker opens"
		)
		panel.typeKey(
			"g",
			modifierFlags: [.command, .shift]
		)
		let path = app.textFields["PathTextField"].firstMatch
		require(
			path,
			predicate: "exists == true",
			description: "Fixture path input opens"
		)
		paste(
			directory.appendingPathComponent("project with spaces").path,
			into: path
		)
		path.typeKey(
			.return,
			modifierFlags: []
		)
		let open = panel.buttons["OKButton"].firstMatch
		require(
			open,
			predicate: "exists == true AND enabled == true AND hittable == true",
			description: "Isolated fixture path is accepted"
		)
		open.click()
	}

	private func verifyAppearance() throws
	{
		let app = try XCTUnwrap(application)
		let image =
			try XCTUnwrap(NSBitmapImageRep(data: app.windows.firstMatch.screenshot()
						.pngRepresentation))
		var samples: [CGFloat] = []
		for x in [0.6, 0.65, 0.7]
		{
			for y in [0.2, 0.25, 0.3]
			{
				let color = try XCTUnwrap(image.colorAt(
					x: Int(Double(image.pixelsWide) * x),
					y: Int(Double(image.pixelsHigh) * y)
				)?.usingColorSpace(.deviceRGB))
				samples
					.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
			}
		}
		let average = samples.reduce(
			0,
			+
		) / CGFloat(samples.count)
		XCTAssertEqual(
			average < 0.5,
			componentAppearance == "Dark",
			"Rendered canvas must match requested appearance; brightness=\(average)"
		)
	}

	private func captureComponent(_ name: String)
	{
		guard let app = application, app.state != .notRunning
		else
		{
			return
		}
		let prefix = "components-" + (componentAppearance ?? "unknown").lowercased() + "-" + name
		if app.windows.firstMatch.exists
		{
			attach(
				XCTAttachment(screenshot: app.windows.firstMatch.screenshot()),
				name: prefix + "-application"
			)
		}
		attach(
			XCTAttachment(string: app.debugDescription),
			name: prefix + "-hierarchy"
		)
	}

	private func verifyCopy(
		_ button: XCUIElement,
		expected: String
	) throws
	{
		let clipboard = NSPasteboard.general
		let saved = (clipboard.pasteboardItems ?? []).map
		{
			item -> NSPasteboardItem in
			let copy = NSPasteboardItem()
			for type in item.types
			{
				if let data = item.data(forType: type)
				{
					copy.setData(
						data,
						forType: type
					)
				}
			}
			return copy
		}
		let sentinel = "copy-probe-" + UUID().uuidString
		clipboard.clearContents()
		let published = clipboard.setString(
			sentinel,
			forType: .string
		)
		let publicationCount = clipboard.changeCount
		var ownedCount = publicationCount
		var ownedValue = clipboard.string(forType: .string)
		var restored = false
		func restoreClipboard()
		{
			guard !restored, clipboard.changeCount == ownedCount,
					clipboard.string(forType: .string) == ownedValue
			else
			{
				return
			}
			clipboard.clearContents()
			clipboard.writeObjects(saved)
			restored = true
		}
		clipboardRestoration = restoreClipboard
		defer
		{
			restoreClipboard()
			clipboardRestoration = nil
		}
		guard published
		else
		{
			restoreClipboard()
			XCTFail("Copy fixture could not publish its clipboard sentinel")
			return
		}
		button.click()
		// Native dispatch is synchronous; retain only this action's publication for cleanup.
		ownedCount = clipboard.changeCount
		ownedValue = clipboard.string(forType: .string)
		let wait = XCTNSPredicateExpectation(
			predicate: NSPredicate
			{
				_, _ in clipboard.changeCount != publicationCount
					&& clipboard.string(forType: .string) == expected
			},
			object: nil
		)
		let result = XCTWaiter.wait(
			for: [wait],
			timeout: 5
		)
		if result == .completed
		{
			ownedCount = clipboard.changeCount
			ownedValue = expected
		}
		// XCTest can abort past Swift defer, so restore before recording a failed assertion.
		restoreClipboard()
		clipboardRestoration = nil
		attach(
			XCTAttachment(string: "Restored copy fixture clipboard: \(restored)"),
			name: "components-" + (componentAppearance ?? "unknown").lowercased()
				+ "-copy-cleanup"
		)
		XCTAssertEqual(
			result,
			.completed,
			"Copy preserves the exact code payload"
		)
	}

	func testSendStreamingMessageAndStop() throws
	{
		let app = try XCTUnwrap(application)
		let directory = try XCTUnwrap(runDirectory)
		if ProcessInfo.processInfo.environment["CODEX_GUI_E2E_COMPACT"] == "1"
		{
			let window = app.windows.firstMatch
			let originalFrame = window.frame
			let right = window.coordinate(withNormalizedOffset: CGVector(
				dx: 1,
				dy: 0.5
			))
			.withOffset(CGVector(
				dx: 2,
				dy: 0
			))
			right.hover()
			right.click(
				forDuration: 0.2,
				thenDragTo: right.withOffset(CGVector(
					dx: -300,
					dy: 0
				))
			)
			let bottom = window.coordinate(withNormalizedOffset: CGVector(
				dx: 0.5,
				dy: 1
			))
			.withOffset(CGVector(
				dx: 0,
				dy: 2
			))
			bottom.hover()
			bottom.click(
				forDuration: 0.2,
				thenDragTo: bottom.withOffset(CGVector(
					dx: 0,
					dy: -160
				))
			)
			step = "Resize native window"
			expectation = "Compact layout shrinks both window dimensions"
			let compact = window.frame.width < originalFrame.width - 50
				&& window.frame.height < originalFrame.height - 50
			if !compact
			{
				collectingFailure = true
			}
			capture(
				"compact",
				target: window,
				issue: compact ? nil : expectation
			)
			XCTAssertTrue(
				compact,
				expectation
			)
		}

		try XCTContext.runActivity(named: "Open the temporary repository through the native picker")
		{
			_ in
			step = "Open repository"
			expectation = "Repository picker opens and accepts the temporary project"
			app.menuBars.menuBarItems["File"].click()
			app.menuBars.menuItems["Open Project…"].click()
			require(
				app.dialogs["open-panel"].firstMatch,
				predicate: "exists == true",
				description: "Repository picker exists before Go to Folder"
			)
			app.dialogs["open-panel"].firstMatch.typeKey(
				"g",
				modifierFlags: [.command, .shift]
			)
			targetIdentifier = "PathTextField"
			let pathField = app.textFields["PathTextField"].firstMatch
			require(
				pathField,
				predicate: "exists == true",
				description: "Go to Folder field exists"
			)
			paste(
				directory.appendingPathComponent("project with spaces").path,
				into: pathField
			)
			pathField.typeKey(
				.return,
				modifierFlags: []
			)
			targetIdentifier = "OKButton"
			let open = app.dialogs["open-panel"].buttons["OKButton"].firstMatch
			require(
				open,
				predicate: "exists == true AND enabled == true AND hittable == true",
				description: "Open Repository is enabled for the temporary project"
			)
			capture(
				"before-open",
				target: open
			)
			open.click()
		}
		XCTContext.runActivity(named: "Select the Markdown streaming conversation")
		{
			_ in
			step = "Select conversation"
			targetIdentifier = "conversation-qa-reading"
			let chat = app.descendants(matching: .any)[targetIdentifier].firstMatch
			require(
				chat,
				predicate: "exists == true AND hittable == true",
				description: "Markdown and streaming chat is available in the sidebar"
			)
			capture(
				"before-select",
				target: chat
			)
			chat.click()
		}
		XCTContext.runActivity(named: "Type and send a message; observe streaming controls")
		{
			_ in
			step = "Send message"
			targetIdentifier = "conversation-composer"
			let composer = app.textViews[targetIdentifier].firstMatch
			require(
				composer,
				predicate: "exists == true AND hittable == true",
				description: "Message composer is available"
			)
			composer.click()
			paste(
				"E2E example: stream Markdown — café 日本語 so I can stop it.",
				into: composer
			)
			let send = app.buttons["conversation-send"].firstMatch
			targetIdentifier = "conversation-send"
			require(
				send,
				predicate: "exists == true AND enabled == true AND hittable == true",
				description: "Send is enabled for the typed message"
			)
			capture(
				"before-send",
				target: send
			)
			send.click()
			let stop = app.buttons["conversation-stop"].firstMatch
			targetIdentifier = "conversation-stop"
			require(
				stop,
				predicate: "exists == true AND enabled == true AND hittable == true",
				description: "Stop appears while the turn is running"
			)
			let streamedText = app.textViews.containing(
				NSPredicate(
					format: "value CONTAINS %@ OR label CONTAINS %@",
					"STREAM_START_MARKER",
					"STREAM_START_MARKER"
				)
			).firstMatch
			require(
				streamedText,
				predicate: "exists == true AND hittable == true",
				description: "First streamed Markdown chunk is visible before Stop"
			)
			streamedPrefix = streamedText.value as? String ?? streamedText.label
			XCTAssertFalse(
				streamedPrefix.isEmpty,
				"Observed stream prefix must not be empty"
			)
			capture(
				"streaming",
				target: streamedText
			)

		}
		XCTContext.runActivity(named: "Stop the turn and preserve the interrupted result")
		{
			_ in
			step = "Stop streaming"
			targetIdentifier = "conversation-stop"
			let stop = app.buttons[targetIdentifier].firstMatch
			require(
				stop,
				predicate: "exists == true AND enabled == true AND hittable == true",
				description: "Stop remains actionable immediately before clicking"
			)
			stop.click()
			let status = app.buttons["workspace-status"].firstMatch
			targetIdentifier = "workspace-status"
			require(
				status,
				predicate: "exists == true AND hittable == true AND label BEGINSWITH 'Stopped.'",
				description: "Execution status becomes Stopped after interrupt acknowledgement"
			)
			require(
				stop,
				predicate: "exists == false OR enabled == false",
				description: "Stop is no longer actionable after interruption"
			)
			let retained = app.textViews.containing(
				NSPredicate(
					format: "value CONTAINS %@ OR label CONTAINS %@",
					"STREAM_START_MARKER",
					"STREAM_START_MARKER"
				)
			).firstMatch
			require(
				retained,
				predicate: "exists == true AND hittable == true",
				description: "Interrupted streamed text remains in the transcript"
			)
			require(
				retained,
				predicate: NSPredicate(
					format: "value BEGINSWITH %@ OR label BEGINSWITH %@",
					streamedPrefix,
					streamedPrefix
				),
				description: "Stopped transcript preserves the complete observed streamed prefix"
			)
			capture(
				"stopped",
				target: status
			)

		}
	}

	/// Use the native paste shortcut to avoid keyboard-layout translation of fixture text.
	private func paste(
		_ text: String,
		into element: XCUIElement,
		focus: Bool = true
	)
	{
		if focus
		{
			element.click()
		}
		let keyboard: XCUIElement = focus ? element : (application ?? element)
		keyboard.typeKey(
			"a",
			modifierFlags: .command
		)
		keyboard.typeKey(
			.delete,
			modifierFlags: []
		)
		let clipboard = NSPasteboard.general
		let saved = (clipboard.pasteboardItems ?? []).map
		{
			item in
			let copy = NSPasteboardItem()
			for type in item.types
			{
				if let data = item.data(forType: type)
				{
					copy.setData(
						data,
						forType: type
					)
				}
			}
			return copy
		}
		clipboard.clearContents()
		let published = clipboard.setString(
			text,
			forType: .string
		)
		let publishedCount = clipboard.changeCount
		let restoreCount = publishedCount
		var restored = false
		func restoreClipboard()
		{
			// XCTest can abort without running Swift defer; restore before assertions too.
			if !restored, clipboard.changeCount == restoreCount
			{
				clipboard.clearContents()
				clipboard.writeObjects(saved)
				restored = true
				clipboardObservation["restoredPreviousClipboard"] = true
			}
		}
		defer
		{
			restoreClipboard()
		}

		let owned = published && clipboard.changeCount == publishedCount
			&& clipboard.string(forType: .string) == text
		clipboardObservation = [
			"publicationSucceeded": published,
			"publishedChangeCount": publishedCount,
			"beforePasteChangeCount": clipboard.changeCount,
			"ownedBeforePaste": owned,
			"restoredPreviousClipboard": false,
		]
		if !owned
		{
			restoreClipboard()
			expectation = "Native clipboard ownership is preserved before paste"
			collectingFailure = true
			capture(
				"failure",
				target: element,
				issue: expectation
			)
			XCTFail(expectation)
			return
		}
		keyboard.typeKey(
			"v",
			modifierFlags: .command
		)
		clipboardObservation["afterPasteChangeCount"] = clipboard.changeCount
		clipboardObservation["changedDuringPaste"] = clipboard.changeCount != publishedCount
		restoreClipboard()

		require(
			element,
			predicate: NSPredicate(
				format: "value == %@",
				text
			),
			description: "Native paste preserves the exact fixture text"
		)
	}

	private func require(
		_ element: XCUIElement,
		predicate: String,
		description: String
	)
	{
		require(
			element,
			predicate: NSPredicate(format: predicate),
			description: description
		)
	}

	private func require(
		_ element: XCUIElement,
		predicate: NSPredicate,
		description: String
	)
	{
		expectation = description
		let wait = XCTNSPredicateExpectation(
			predicate: predicate,
			object: element
		)
		let result = XCTWaiter.wait(
			for: [wait],
			timeout: 12
		)
		if result != .completed
		{
			collectingFailure = true
			capture(
				"failure",
				target: element,
				issue: "Timed out: " + description
			)
		}
		XCTAssertEqual(
			result,
			.completed,
			description
		)
	}

	private func capture(
		_ name: String,
		target: XCUIElement? = nil,
		issue: String? = nil
	)
	{
		guard let app = application
		else
		{
			return
		}
		checkpointNumber += 1
		let prefix = String(
			format: "%02d-%@",
			checkpointNumber,
			name
		)
		let started = Date().timeIntervalSince1970
		let stateURL = runDirectory?.appendingPathComponent("state-history.json")
		let stateBefore = stateURL.flatMap
		{
			try? Data(contentsOf: $0)
		}
		for file in ["state-history.json", "backend-trace.jsonl", "fixture.json"]
		{
			if let directory = runDirectory,
				let data = file == "state-history.json" ? stateBefore
				: (try? Data(contentsOf: directory.appendingPathComponent(file)))
			{
				attach(
					XCTAttachment(
						data: data,
						uniformTypeIdentifier: "public.data"
					),
					name: prefix + "-" + file
				)
			}
		}
		attach(
			XCTAttachment(string: "Step: " + step + "\nExpected: " + expectation
				+ "\nIssue: " + (issue ?? "") + "\nLast named control: " + targetIdentifier),
			name: prefix + "-failure-context"
		)
		// Preserve the desktop image even if the app has no accessible window after a crash.
		let screen = XCUIScreen.main.screenshot()
		attach(
			XCTAttachment(screenshot: screen),
			name: prefix + "-screen"
		)
		let dialog = app.dialogs.firstMatch
		let window = app.windows.firstMatch
		let running = app.state != .notRunning
		let region = running && dialog.exists ? dialog : window
		let hasRegion = running && region.exists
		let foreground = hasRegion ? region.screenshot() : screen
		attach(
			XCTAttachment(screenshot: foreground),
			name: prefix + "-application"
		)

		let element = target ?? app.descendants(matching: .any)[targetIdentifier].firstMatch
		var details: [String: Any] = [
			"schemaVersion": 2,
			"step": step,
			"expected": expectation,
			"issue": issue ?? "",
			"lastNamedControlIdentifier": targetIdentifier,
			"clipboardObservation": clipboardObservation,
			"targetQuery": String(describing: element),
			"captureStarted": started,
			"applicationState": app.state.rawValue,
			"coordinateSpace": "XCUI screen points; "
				+ "screenshot pixels require scale conversion",
			"evidenceKind": "launched app with supplied QA backend",
			"applicationImageScope": hasRegion ? "foreground-region" : "screen-fallback",
			"applicationImageFrame": hasRegion ? NSStringFromRect(region.frame) : "",
		]
		if let pixels = NSBitmapImageRep(data: foreground.pngRepresentation)
		{
			details["applicationImagePixels"] = [
				"width": pixels.pixelsWide,
				"height": pixels.pixelsHigh,
			]
		}
		if running && element.exists
		{
			details["target"] = [
				"identifier": element.identifier,
				"label": element.label,
				"value": String(describing: element.value ?? ""),
				"enabled": element.isEnabled,
				"hittable": element.isHittable,
				"frame": NSStringFromRect(element.frame),
			]
			if element.isHittable
			{
				attach(
					XCTAttachment(screenshot: element.screenshot()),
					name: prefix + "-target"
				)
			}
		}
		else
		{
			details["targetMissing"] = true
		}
		details["windowFrames"] = running ? app.windows.allElementsBoundByIndex.map
		{
			["title": $0.label, "frame": NSStringFromRect($0.frame)]
		} : []
		attach(
			XCTAttachment(string: running ? app.debugDescription
				: "Unavailable: application is not running; use the last state history"),
			name: prefix + "-ui-hierarchy"
		)
		for file in ["state-history.json", "backend-trace.jsonl", "fixture.json"]
		{
			if let directory = runDirectory,
				!FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path)
			{
				details["unavailable-" + file] = true
			}
		}
		if let stateURL, let after = try? Data(contentsOf: stateURL)
		{
			let beforeRows = stateBefore.flatMap
			{
				try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
			}
			let afterRows = try? JSONSerialization.jsonObject(with: after) as? [[String: Any]]
			details["stateSequenceBefore"] = beforeRows?.last?["sequence"]
			details["stateSequenceAfter"] = afterRows?.last?["sequence"]
			details["stateChangedDuringCapture"] = stateBefore != after
			attach(
				XCTAttachment(
					data: after,
					uniformTypeIdentifier: "public.data"
				),
				name: prefix + "-state-after.json"
			)
		}
		details["captureFinished"] = Date().timeIntervalSince1970
		if let data = try? JSONSerialization.data(
			withJSONObject: details,
			options: [.prettyPrinted]
		)
		{
			attach(
				XCTAttachment(
					data: data,
					uniformTypeIdentifier: "public.json"
				),
				name: prefix + "-checkpoint.json"
			)
		}
	}

	private func attach(
		_ attachment: XCTAttachment,
		name: String
	)
	{
		attachment.name = name
		attachment.lifetime = .keepAlways
		add(attachment)
	}

	private enum EvidenceError: Error
	{
		case invalidRunDirectory
	}
}
