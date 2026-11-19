import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite(.appKitIsolation)
struct SettingsVoicePageTests
{
	@Test func groupsIncludeOnlyAdvertisedVoicesWithVerifiedLabels()
	{
		let choices = SettingsVoicePage.choices(for: ["rio", "rindo", "juniper", "tinta", "porto"])
		#expect(choices.map(\.id) == ["", "porto", "juniper", "rio", "rindo", "tinta"])
		#expect(choices.map(\.section) == [
			nil,
			nil,
			"American English",
			"Brazilian Portuguese",
			"Japanese",
			"Mexican Spanish",
		])
		#expect(choices.first
		{
			$0.id == "rindo"
		}?.title == "Rindō")
	}

	@Test func previewUsesTheUnsavedVoiceAndRetiresItsSpeechSession() async throws
	{
		try await withPage(mode: "preview")
		{
			page, backend in
			let loading = try #require(page.loading)
			await loading.value
			let sheet = try openSheet(page)
			let shell = try #require(sheet.contentView as? DesktopDialogShell)
			let actions = shell.actionsRow.arrangedSubviews.compactMap
			{
				$0 as? NSButton
			}
			#expect(actions.map(\.title) == ["Cancel", "Done"])
			shell.layoutSubtreeIfNeeded()
			let scroll = try #require(descendants(shell).compactMap
			{
				$0 as? NSScrollView
			}.first)
			let document = try #require(scroll.documentView)
			#expect(document.bounds.height > scroll.contentView.bounds.height)
			#expect(actions.allSatisfy
			{
				!$0.isDescendant(of: scroll)
			})
			let row = try row(
				titled: "Rindō",
				in: sheet
			)
			#expect(row.accessibilityPerformPress())
			#expect(row.checked)
			#expect(page.chooseButton.title == "Juniper")
			#expect(backend.value("realtime.voice") as? String == "juniper")
			let preview = try #require(page.previewTask)
			await preview.value
			let result = try await backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(result["writes"] as? Int == 0)
			#expect(result["previewVoices"] as? [String] == ["rindo"])
			#expect(result["sampleTexts"] as? [String] == [
				"こんにちは。この声の短いサンプルをお聞きください。",
			])
			#expect(result["retiredThreads"] as? [String] == ["private-preview"])
			#expect(backend.value("realtime.voice") as? String == "juniper")
		}
	}

	@Test func cancelDiscardsThePendingChoice()
		async throws
	{
		try await withPage(mode: "preview")
		{
			page, backend in
			let loading = try #require(page.loading)
			await loading.value
			let sheet = try openSheet(page)
			let pending = try row(
				titled: "Rindō",
				in: sheet
			)
			#expect(pending.accessibilityPerformPress())
			#expect(pending.checked)
			let cancel = try button(
				titled: "Cancel",
				in: sheet
			)
			#expect(cancel.dispatchConfiguredAction())
			#expect(page.sheet == nil)
			#expect(backend.value("realtime.voice") as? String == "juniper")
			let reopened = try openSheet(page)
			#expect(try row(
				titled: "Juniper",
				in: reopened
			).checked)
		}
	}

	@Test func olderCatalogDoesNotOfferVoicesTheGUICannotStart() async throws
	{
		try await withPage(mode: "legacy")
		{
			page, backend in
			let loading = try #require(page.loading)
			await loading.value
			#expect(!page.chooseButton.isEnabled)
			#expect(!page.chooseButton.dispatchConfiguredAction())
			#expect(page.sheet == nil)
			let counts = try await backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(counts["voiceReads"] as? Int == 1)
		}
	}

	@Test func reconnectRefetchesTheCatalogAndRecoversFromATransientReadFailure() async throws
	{
		try await withPage(mode: "retry")
		{
			page, backend in
			let initialLoad = try #require(page.loading)
			await initialLoad.value
			#expect(page.chooseButton.isEnabled)
			let initialCounts = try await backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(initialCounts["voiceReads"] as? Int == 2)
			backend.stop()
			#expect(!page.chooseButton.isEnabled)
			await backend.start()
			let reconnectLoad = try #require(page.loading)
			await reconnectLoad.value
			#expect(page.chooseButton.isEnabled)
			let reconnectCounts = try await backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(reconnectCounts["voiceReads"] as? Int == 2)
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func defaultCanClearAHiddenIncompatibleStoredVoiceEvenWithoutAV3Catalog() async throws
	{
		try await withPage(mode: "invalid")
		{
			page, backend in
			let loading = try #require(page.loading)
			await loading.value
			#expect(page.chooseButton.isEnabled)
			let sheet = try openSheet(page)
			#expect(rows(in: sheet).map(\.title) == ["Default"])
			let defaultRow = try row(
				titled: "Default",
				in: sheet
			)
			#expect(!defaultRow.checked)
			#expect(defaultRow.accessibilityPerformPress())
			#expect(backend.value("realtime.voice") as? String == "marin")
			let done = try button(
				titled: "Done",
				in: sheet
			)
			#expect(done.dispatchConfiguredAction())
			let save = try #require(page.saveTask)
			await save.value
			#expect(backend.value("realtime.voice") == nil)
			#expect(!page.chooseButton.isEnabled)
		}
	}

	private func withPage(
		mode: String,
		observe: @MainActor (
			SettingsVoicePage,
			SettingsBackend
		) async throws -> Void
	) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: Self.script.replacingOccurrences(
				of: "TEST_MODE",
				with: mode
			)
		)
		let backend = SettingsBackend(server: AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		))
		defer
		{
			backend.stop()
		}
		await backend.start()
		_ = NSApplication.shared
		let page = SettingsVoicePage(backend: backend)
		backend.onChange =
		{
			[weak page] in page?.refresh()
		}
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 600,
				height: 400
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		window.contentView = page
		defer
		{
			window.contentView = nil
			window.close()
		}
		try await observe(
			page,
			backend
		)
	}

	private func openSheet(_ page: SettingsVoicePage) throws -> SettingsVoiceSheet
	{
		try #require(page.chooseButton.dispatchConfiguredAction())
		let sheet = try #require(page.sheet)
		#expect(page.window?.attachedSheet === sheet)
		return sheet
	}

	private func rows(in sheet: SettingsVoiceSheet) -> [SettingsChoiceMenuRow]
	{
		sheet.contentView.map(descendants)?.compactMap
		{
			$0 as? SettingsChoiceMenuRow
		} ?? []
	}

	private func row(
		titled title: String,
		in sheet: SettingsVoiceSheet
	) throws -> SettingsChoiceMenuRow
	{
		try #require(rows(in: sheet).first
		{
			$0.title == title
		})
	}

	private func button(
		titled title: String,
		in sheet: SettingsVoiceSheet
	) throws -> NSButton
	{
		let content = try #require(sheet.contentView)
		return try #require(descendants(content).compactMap
		{
			$0 as? NSButton
		}
		.first
		{
			$0.title == title
		})
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import sys, json
	if '--version' in sys.argv:
	    print('codex-cli 0.169.0')
	    sys.exit(0)
	mode = 'TEST_MODE'
	voice_reads = 0
	writes = 0
	preview_voices, sample_texts, retired_threads = [], [], []
	realtime = {'version':'v2'}
	if mode == 'invalid': realtime['voice'] = 'marin'
	if mode == 'preview': realtime['voice'] = 'juniper'
	def notify(method, params):
	    print(json.dumps({'method':method, 'params':params}), flush=True)
	for line in sys.stdin:
	    message = json.loads(line)
	    method, params = message.get('method'), message.get('params', {})
	    if method is None or method == 'initialized': continue
	    if method == 'initialize': result = {'userAgent':'mock'}
	    elif method == 'config/read':
	        config = {'realtime':realtime}
	        if mode == 'preview':
	            config['model_providers'] = {'openai':{'experimental_bearer_token':'mock'}}
	        result = {'config':config,'origins':{},'layers':[]}
	    elif method == 'configRequirements/read': result = {'requirements':{}}
	    elif method == 'experimentalFeature/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'thread/realtime/listVoices':
	        voice_reads += 1
	        if mode == 'retry' and voice_reads == 1:
	            print(json.dumps({'id':message['id'],'error':{
	                'code':-32603,'message':'Temporary read failure'}}), flush=True)
	            continue
	        voices = {'v1':['cove'],'v2':['marin'],'defaultV1':'cove','defaultV2':'marin'}
	        if mode == 'retry': voices['v3'] = ['juniper','cove']
	        if mode == 'preview':
	            voices['v3'] = ['juniper','rindo','cove','maple','rio','viola',
	                            'aube','rivage','neer','leher','hanul','haetsal','tinta']
	        result = {'voices':voices}
	    elif method == 'config/batchWrite':
	        writes += 1
	        assert params['edits'] == [
	            {'keyPath':'realtime.voice','value':None,'mergeStrategy':'replace'}]
	        realtime.pop('voice')
	        result = {'status':'ok','version':'2'}
	    elif method == 'thread/start' and mode == 'preview':
	        assert params['ephemeral'] and params['sandbox'] == 'read-only'
	        result = {'thread':{'id':'private-preview'}}
	    elif method == 'thread/realtime/start' and mode == 'preview':
	        assert params['version'] == 'v3' and params['threadId'] == 'private-preview'
	        assert params['transport'] == {'type':'websocket'}
	        preview_voices.append(params['voice'])
	        notify('thread/realtime/started', {'threadId':'private-preview','version':'v3'})
	        result = {}
	    elif method == 'thread/realtime/appendSpeech' and mode == 'preview':
	        sample_texts.append(params['text'])
	        notify('thread/realtime/transcript/done', {
	            'threadId':'private-preview','role':'assistant'})
	        result = {}
	    elif method == 'thread/realtime/stop' and mode == 'preview':
	        assert params['threadId'] == 'private-preview'
	        result = {}
	    elif method == 'thread/unsubscribe' and mode == 'preview':
	        retired_threads.append(params['threadId'])
	        result = {}
	    elif method == 'test/counts':
	        result = {'voiceReads':voice_reads,'writes':writes,'previewVoices':preview_voices,
	                  'sampleTexts':sample_texts,'retiredThreads':retired_threads}
	    else:
	        print(json.dumps({'id':message['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':message['id'],'result':result}), flush=True)
	"""#
}
