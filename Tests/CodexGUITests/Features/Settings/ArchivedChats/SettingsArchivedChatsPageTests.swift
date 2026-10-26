import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsArchivedChatsPageTests
{
	@Test func paginatedArchiveSupportsBoundedGroupsCombinedFiltersAndUnarchive() async throws
	{
		let fixture = try await ArchivedChatsPageFixture.make()
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		#expect(fixture.backend.isConnected)
		try await AppKitTestIsolation.perform
		{
			let page = SettingsArchivedChatsPage(
				backend: fixture.backend,
				readProjectContext:
				{
					SettingsArchivedProjectContext()
				}
			)
			let window = makeWindow(page: page)
			defer
			{
				window.close()
			}
			page.refresh()
			let loading = try #require(page.operation)
			await loading.value
			#expect(page.operation == nil)
			#expect(page.message.isEmpty)
			let archive = try archiveView(in: page)
			#expect(archive.matchingCount == 125)
			#expect(archive.visibleChatIDs.count == 50)
			#expect(unarchiveButtons(in: archive).count == 50)
			#expect(Set(archive.visibleChatIDs.prefix(3)) == [
				"thread-000",
				"thread-001",
				"thread-002"
			])
			if ProcessInfo.processInfo.environment["CODEX_GUI_ARCHIVE_PREVIEW"] != nil
			{
				window.appearance = NSAppearance(named: .aqua)
				window.orderFront(nil)
				try snapshot(
					try #require(window.contentView),
					suffix: "archive-grouped"
				)
				try snapshotMenu(
					in: archive,
					label: "Archived chat type and sort",
					suffix: "archive-type-sort-menu"
				)
				try snapshotMenu(
					in: archive,
					label: "Archived chat project",
					suffix: "archive-project-menu"
				)
			}

			archive.setSearch("Needle from second backend page")
			#expect(archive.matchingCount == 1)
			#expect(archive.visibleChatIDs == ["thread-124"])
			let project = try #require(descendants(archive).compactMap
			{
				$0 as? SettingsChoicePicker
			}
			.first
			{
				$0.accessibilityLabel() == "Archived chat project"
			})
			project.onSelect?("project:alpha")
			#expect(archive.matchingCount == 0)
			archive.setSearch("")
			archive.selectFilter("type:local")
			#expect(archive.matchingCount == 61)
			archive.selectFilter("sort:created")
			#expect(archive.visibleChatIDs.first == "thread-063")
			archive.selectFilter("sort:updated")
			#expect(archive.visibleChatIDs.first == "thread-003")
			archive.selectFilter("sort:alphabetical")
			#expect(archive.visibleChatIDs.first == "thread-003")
			archive.showPage(1)
			#expect(archive.visibleChatIDs.count == 11)
			#expect(unarchiveButtons(in: archive).count == 11)

			project.onSelect?("all")
			archive.selectFilter("type:all")
			archive.setSearch("Needle from second backend page")
			try snapshot(
				try #require(window.contentView),
				suffix: "archive-search-results"
			)
			let unarchive = try #require(unarchiveButtons(in: archive).first)
			#expect(unarchive.dispatchConfiguredAction())
			let mutation = try #require(page.operation)
			await mutation.value
			#expect(page.operation == nil)
			#expect(page.message.isEmpty)
			#expect(archive.matchingCount == 0)
			archive.setSearch("")
			#expect(archive.matchingCount == 124)
			#expect(unarchiveButtons(in: archive).count <= 50)
			let counts = try await fixture.backend.perform(
				"test/counts",
				params: [:]
			)
			#expect(counts["threadReads"] as? Int == 2)
			#expect(counts["projectReads"] as? Int == 2)
			#expect(counts["unarchived"] as? [String] == ["thread-124"])
			#expect(counts["deletes"] as? Int == 0)
		}
	}

	@Test func detachedPageCannotPublishArchiveAfterPendingContextReadCompletes() async throws
	{
		let fixture = try await ArchivedChatsPageFixture.make()
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		let gate = ArchivedProjectContextGate()
		defer
		{
			gate.release()
		}
		let page = SettingsArchivedChatsPage(
			backend: fixture.backend,
			readProjectContext:
			{
				await gate.read()
			}
		)
		let window = makeWindow(page: page)
		defer
		{
			window.close()
		}
		page.refresh()
		let loading = try #require(page.operation)
		#expect(await gate.waitUntilEntered(or: loading))
		let archive = try archiveView(in: page)
		#expect(archive.matchingCount == 0)
		window.contentView = NSView()
		#expect(loading.isCancelled)
		gate.release()
		await loading.value
		// A later ordinary render must not resurrect data from the retired load.
		page.render()
		#expect(page.operation == nil)
		#expect(archive.matchingCount == 0)
		#expect(archive.visibleChatIDs.isEmpty)
		let counts = try await fixture.backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["threadReads"] as? Int == 2)
		#expect(counts["projectReads"] as? Int == 2)
		#expect(counts["unarchived"] as? [String] == [])
	}

	private func snapshotMenu(
		in view: NSView,
		label: String,
		suffix: String
	) throws
	{
		let picker = try #require(descendants(view).compactMap
		{
			$0 as? SettingsChoicePicker
		}
		.first
		{
			$0.accessibilityLabel() == label
		})
		#expect(picker.dispatchConfiguredAction())
		defer
		{
			_ = picker.dispatchConfiguredAction()
		}
		let menu = try #require(picker.window?.childWindows?.first(where:
			{
				$0.isVisible
			})?
			.contentView)
		try snapshot(
			menu,
			suffix: suffix
		)
	}

	private func snapshot(
		_ view: NSView,
		suffix: String
	) throws
	{
		guard let directory = ProcessInfo.processInfo.environment["CODEX_GUI_ARCHIVE_PREVIEW"]
		else
		{
			return
		}
		let output = URL(
			fileURLWithPath: directory,
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
			to: output.appendingPathComponent(suffix + ".png")
		)
	}

	private func makeWindow(page: NSView) -> NSWindow
	{
		_ = NSApplication.shared
		let window = NSWindow(
			contentRect: NSRect(
				x: 0,
				y: 0,
				width: 1000,
				height: 760
			),
			styleMask: [.titled],
			backing: .buffered,
			defer: false
		)
		window.prepareForTesting()
		let canvas = SettingsSurfaceView(color: AppKitColorTokens.canvas)
		window.contentView = canvas
		AppKitLayout.pin(
			page,
			to: canvas,
			inset: 0
		)
		return window
	}

	private func archiveView(in view: NSView) throws -> SettingsArchivedChatsView
	{
		try #require(descendants(view).compactMap
		{
			$0 as? SettingsArchivedChatsView
		}.first)
	}

	private func unarchiveButtons(in view: NSView) -> [NSButton]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.filter
		{
			$0.title == "Unarchive"
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}

@MainActor
private final class ArchivedProjectContextGate
{
	private var entered = false
	private var entryWaiter: CheckedContinuation<Bool, Never>?
	private var released = false
	private var releaseWaiter: CheckedContinuation<Void, Never>?

	func read() async -> SettingsArchivedProjectContext
	{
		if released
		{
			return SettingsArchivedProjectContext()
		}
		await withCheckedContinuation
		{
			continuation in
			releaseWaiter = continuation
			entered = true
			entryWaiter?.resume(returning: true)
			entryWaiter = nil
		}
		return SettingsArchivedProjectContext()
	}

	func waitUntilEntered(or operation: Task<Void, Never>) async -> Bool
	{
		if entered
		{
			return true
		}
		let completion = Task
		{
			[weak self] in
			await operation.value
			self?.entryWaiter?.resume(returning: false)
			self?.entryWaiter = nil
		}
		defer
		{
			completion.cancel()
		}
		return await withCheckedContinuation
		{
			entryWaiter = $0
		}
	}

	func release()
	{
		released = true
		releaseWaiter?.resume()
		releaseWaiter = nil
	}
}

@MainActor
private struct ArchivedChatsPageFixture
{
	let directory: URL
	let backend: SettingsBackend

	func close()
	{
		backend.stop()
		try? FileManager.default.removeItem(at: directory)
	}

	static func make() async throws -> ArchivedChatsPageFixture
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		do
		{
			let executable = try await AppServerTestExecutable.mockExecutable(
				in: directory,
				script: script
			)
			return ArchivedChatsPageFixture(
				directory: directory,
				backend: SettingsBackend(server: AppServer(
					executableOverride: executable,
					requestTimeout: .seconds(10)
				))
			)
		}
		catch
		{
			try? FileManager.default.removeItem(at: directory)
			throw error
		}
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import sys, json
	if '--version' in sys.argv:
	    print('codex-cli 0.163.0')
	    sys.exit(0)
	threads = []
	for index in range(125):
	    title = 'Needle from second backend page' if index == 124 else f'Chat {index:03d}'
	    threads.append({'id':f'thread-{index:03d}', 'name':title, 'preview':'',
	        'cwd':'' if index < 3 else '/alpha' if index < 64 else '/beta',
	        'projectId':None if index < 3 else 'alpha' if index < 64 else 'beta',
	        'createdAt':1000 + index, 'updatedAt':2000 - index, 'source':'appServer'})
	projects = [{'id':'alpha','name':'Alpha','roots':[{'path':'/alpha'}]},
	    {'id':'beta','name':'Beta','roots':[{'path':'/beta'}]}]
	thread_reads, project_reads, deletes = 0, 0, 0
	unarchived = []
	for line in sys.stdin:
	    request = json.loads(line)
	    method, params = request.get('method'), request.get('params', {})
	    if method is None or method == 'initialized': continue
	    if method == 'initialize': result = {'userAgent':'mock'}
	    elif method == 'config/read':
	        result = {'config':{'model':'fixture-model'}, 'origins':{}, 'layers':[
	            {'name':{'type':'user','file':'/fixture/config.toml'},
	             'config':{'model':'fixture-model'}, 'version':'1'}]}
	    elif method == 'configRequirements/read': result = {'requirements':{}}
	    elif method == 'experimentalFeature/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'model/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'thread/list':
	        assert params['archived'] is True and params['limit'] == 100
	        thread_reads += 1
	        second = params.get('cursor') == 'thread-page-2'
	        result = {'data':threads[100:] if second else threads[:100],
	            'nextCursor':None if second else 'thread-page-2'}
	    elif method == 'project/list':
	        assert params['limit'] == 100
	        project_reads += 1
	        second = params.get('cursor') == 'project-page-2'
	        result = {'data':projects[1:] if second else projects[:1],
	            'nextCursor':None if second else 'project-page-2'}
	    elif method == 'thread/unarchive':
	        thread_id = params['threadId']
	        assert any(thread['id'] == thread_id for thread in threads)
	        unarchived.append(thread_id)
	        threads = [thread for thread in threads if thread['id'] != thread_id]
	        result = {}
	    elif method == 'thread/delete':
	        deletes += 1
	        result = {}
	    elif method == 'test/counts':
	        result = {'threadReads':thread_reads, 'projectReads':project_reads,
	            'unarchived':unarchived, 'deletes':deletes}
	    else:
	        print(json.dumps({'id':request['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':request['id'],'result':result}), flush=True)
	"""#
}
