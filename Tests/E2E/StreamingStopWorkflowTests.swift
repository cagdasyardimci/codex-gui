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
		app.launch()

	}

	override func tearDown() async throws
	{
		if (testRun?.totalFailureCount ?? 0) > 0, !collectingFailure
		{
			capture(
				"failure-in-teardown",
				issue: "Unexpected XCTest failure; see test results"
			)
		}
		application?.terminate()
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
		into element: XCUIElement
	)
	{
		element.click()
		element.typeKey(
			"a",
			modifierFlags: .command
		)
		element.typeKey(
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
		element.typeKey(
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
