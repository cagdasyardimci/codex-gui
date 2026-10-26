import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsConfigurationPageTests
{
	@Test(.timeLimit(.minutes(1)))
	func advertisedEffortsWireRequiredChecksAndOptionalVisibilityWithoutClosingMenu() async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: Self.script
		)
		let backend = SettingsBackend(server: AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(10)
		))
		defer
		{
			backend.stop()
		}
		await backend.start()
		#expect(backend.isConnected)
		#expect(backend.status.isEmpty)
		let suite = "SettingsConfigurationPageTests.\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		defer
		{
			defaults.removePersistentDomain(forName: suite)
		}
		let visibility = ReasoningEffortVisibility(defaults: defaults)
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let page = SettingsConfigurationPage(
				backend: backend,
				effortVisibility: visibility
			)
			let loading = try #require(page.effortLoading)
			await loading.value
			#expect(page.effortLoading == nil)
			let picker = try #require(descendants(page).compactMap
			{
				$0 as? SettingsChoicePicker
			}.first
			{
				$0.accessibilityLabel() == "Available reasoning efforts"
			})
			#expect(picker.title == "6 selected")
			#expect(!picker.usesCheckboxesForMultipleSelection)
			let counts = try await backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(counts["modelReads"] as? Int == 2)
			let window = NSWindow(
				contentRect: NSRect(
					x: 100,
					y: 100,
					width: 1100,
					height: 820
				),
				styleMask: [.titled],
				backing: .buffered,
				defer: false
			)
			window.prepareForTesting()
			window.appearance = NSAppearance(named: .aqua)
			let canvas = SettingsSurfaceView(color: AppKitColorTokens.canvas)
			window.contentView = canvas
			AppKitLayout.pin(
				page,
				to: canvas,
				inset: 0
			)
			window.orderFront(nil)
			defer
			{
				page.removeFromSuperview()
				window.close()
			}
			window.layoutIfNeeded()
			canvas.layoutSubtreeIfNeeded()
			let labels = descendants(page).compactMap
			{
				($0 as? NSTextField)?.stringValue
			}
			#expect(!labels.contains
			{
				$0.contains("This changes picker visibility")
			})
			#expect(!labels.contains
			{
				$0.contains("Changes apply to new chats.")
			})
			#expect(!labels.contains
			{
				$0.contains("Dependency bundle installation is managed separately.")
			})
			try capture(
				canvas,
				name: "configuration-page.png"
			)
			picker.scrollToVisible(picker.bounds)
			#expect(picker.dispatchConfiguredAction())
			let panel = try #require(window.childWindows?.first)
			let menu = try #require(panel.contentView)
			let rows = descendants(menu).compactMap
			{
				$0 as? NSButton
			}
			#expect(rows.map(\.title) == ["Light", "Medium", "High", "Extra High", "Max", "Ultra"])
			for row in rows.prefix(4)
			{
				#expect(row.state == .on)
				#expect(!row.isEnabled)
			}
			let max = try #require(rows.first
			{
				$0.title == "Max"
			})
			let ultra = try #require(rows.first
			{
				$0.title == "Ultra"
			})
			#expect(max.isEnabled && ultra.isEnabled)
			#expect(max.state == .on && ultra.state == .on)
			try captureMenu(menu)
			#expect(max.dispatchConfiguredAction())
			#expect(picker.title == "5 selected")
			#expect(panel.isVisible)
			#expect(max.state == .off)
			#expect(ultra.state == .on)
			#expect(!visibility.isVisible("max"))
			#expect(defaults.stringArray(forKey: "settings.hiddenReasoningEfforts") == ["max"])
			picker.onToggle?("low", false)
			#expect(visibility.isVisible("low"))
			#expect(picker.title == "5 selected")
			#expect(rows.first?.state == .on)
			#expect(panel.isVisible)
			#expect(defaults.stringArray(forKey: "settings.hiddenReasoningEfforts") == ["max"])
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}

	private func capture(
		_ view: NSView,
		name: String
	) throws
	{
		guard let path = ProcessInfo.processInfo.environment["CODEX_GUI_CONFIGURATION_PREVIEW"]
		else
		{
			return
		}
		let output = URL(
			fileURLWithPath: path,
			isDirectory: true
		)
		try FileManager.default.createDirectory(
			at: output,
			withIntermediateDirectories: true
		)
		view.window?.layoutIfNeeded()
		view.layoutSubtreeIfNeeded()
		for child in descendants(view)
		{
			child.needsDisplay = true
		}
		view.display()
		try AppTestPNGWriter.write(
			view,
			to: output.appendingPathComponent(name)
		)
	}

	private func captureMenu(_ content: NSView) throws
	{
		guard ProcessInfo.processInfo.environment["CODEX_GUI_CONFIGURATION_PREVIEW"] != nil
		else
		{
			return
		}
		let background = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		background.frame = content.bounds
		content.addSubview(
			background,
			positioned: .below,
			relativeTo: content.subviews.first
		)
		defer
		{
			background.removeFromSuperview()
		}
		try capture(
			content,
			name: "configuration-effort-menu.png"
		)
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import sys, json
	if '--version' in sys.argv:
	    print('codex-cli 0.163.0')
	    sys.exit(0)
	model_reads = 0
	for line in sys.stdin:
	    request = json.loads(line)
	    method, params = request.get('method'), request.get('params', {})
	    if method is None or method == 'initialized': continue
	    if method == 'initialize': result = {'userAgent':'mock'}
	    elif method == 'config/read':
	        result = {'config':{'approval_policy':'on-request','sandbox_mode':'workspace-write',
	            'sandbox_workspace_write':{'network_access':False}},'origins':{},'layers':[]}
	    elif method == 'configRequirements/read': result = {'requirements':{}}
	    elif method == 'experimentalFeature/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'model/list':
	        model_reads += 1
	        cursor = params.get('cursor')
	        assert cursor in (None, 'second')
	        efforts = (['ultra','medium','low'] if cursor is None
	            else ['max','xhigh','high','medium'])
	        result = {'data':[{'model':'fixture-' + str(model_reads),
	            'supportedReasoningEfforts':[{'reasoningEffort':e} for e in efforts]}],
	            'nextCursor':'second' if cursor is None else None}
	    elif method == 'test/counts': result = {'modelReads':model_reads}
	    else:
	        print(json.dumps({'id':request['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':request['id'],'result':result}), flush=True)
	"""#
}
