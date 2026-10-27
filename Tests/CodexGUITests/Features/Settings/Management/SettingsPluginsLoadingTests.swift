import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsPluginsLoadingTests
{
	@Test func populatedCatalogLoadsInstalledPluginsAndBoundsNativeRowsWhileBrowsing() async throws
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

		_ = NSApplication.shared
		let page = SettingsPluginsPage(backend: backend)
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
		window.contentView = page
		defer
		{
			window.close()
		}
		page.refresh()
		let loading = try #require(page.operation)
		await loading.value
		window.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		#expect(page.operation == nil)
		#expect(!backend.isBusy)

		let catalog = try #require(descendants(page).compactMap
		{
			$0 as? SettingsPluginsCatalogView
		}.first)
		#expect(catalog.matchingCount == 18)
		#expect(catalog.visiblePluginIDs.count == 18)
		#expect(pluginActionCount(in: catalog) == 18)
		let installedActions = pluginActions(in: catalog)
		#expect(Set(installedActions.compactMap
			{
				$0.accessibilityLabel()
			}) == Set((0 ..< 18).map
		{
			String(
				format: "View Fixture plugin %05d",
				$0
			)
		}))

		catalog.setFilter(installedOnly: false)
		window.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		#expect(catalog.matchingCount == 8500)
		#expect(catalog.visiblePluginIDs.count == SettingsPluginsCatalogView.pageSize)
		#expect(pluginActionCount(in: catalog) <= 40)
		let firstPage = Set(catalog.visiblePluginIDs)
		catalog.showPage(1)
		window.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		#expect(catalog.visiblePluginIDs.count == 40)
		#expect(firstPage.isDisjoint(with: Set(catalog.visiblePluginIDs)))
		#expect(pluginActionCount(in: catalog) <= 40)

		catalog.setSearch("Fixture plugin 08499")
		window.layoutIfNeeded()
		page.layoutSubtreeIfNeeded()
		#expect(catalog.matchingCount == 1)
		#expect(catalog.visiblePluginIDs == ["plugin-08499"])
		#expect(pluginActionCount(in: catalog) == 1)
		catalog.setSearch("")
		catalog.setFilter(installedOnly: true)
		#expect(catalog.matchingCount == 18)
		#expect(catalog.visiblePluginIDs.count == 18)
		#expect(pluginActionCount(in: catalog) == 18)

		let counts = try await backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["pluginReads"] as? Int == 1)
	}

	private func pluginActionCount(in view: NSView) -> Int
	{
		pluginActions(in: view).count
	}

	private func pluginActions(in view: NSView) -> [NSButton]
	{
		descendants(view).compactMap
		{
			$0 as? NSButton
		}.filter
		{
			$0.title == "Install" || $0.accessibilityLabel()?.hasPrefix("View ") == true
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}

	private static let script = #"""
	#!/usr/bin/env python3
	import sys, json
	if '--version' in sys.argv:
	    print('codex-cli 0.163.0')
	    sys.exit(0)
	plugin_reads = 0
	marketplaces = []
	offset = 0
	for market_index, count in enumerate([5, 7, 315, 8173]):
	    plugins = []
	    for index in range(offset, offset + count):
	        name = f'Fixture plugin {index:05d}'
	        plugins.append({'id':f'plugin-{index:05d}', 'name':name,
	            'enabled':True, 'installed':index < 18,
	            'authPolicy':'ON_USE', 'installPolicy':'AVAILABLE',
	            'availability':'AVAILABLE', 'source':{'type':'local','path':'/fixture/plugins'},
	            'interface':{'displayName':name, 'shortDescription':'Fixture plugin description'}})
	    marketplaces.append({'name':f'marketplace-{market_index}',
	        'path':f'/fixture/marketplace-{market_index}', 'plugins':plugins})
	    offset += count
	for line in sys.stdin:
	    request = json.loads(line)
	    method = request.get('method')
	    if method is None or method == 'initialized': continue
	    if method == 'initialize': result = {'userAgent':'mock'}
	    elif method == 'config/read':
	        result = {'config':{'model':'fixture-model'}, 'origins':{}, 'layers':[
	            {'name':{'type':'user','file':'/fixture/config.toml'},
	             'config':{'model':'fixture-model'}, 'version':'1'}]}
	    elif method == 'configRequirements/read': result = {'requirements':{}}
	    elif method == 'experimentalFeature/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'model/list': result = {'data':[], 'nextCursor':None}
	    elif method == 'plugin/list':
	        plugin_reads += 1
	        result = {'marketplaces':marketplaces, 'marketplaceLoadErrors':[]}
	    elif method == 'test/counts': result = {'pluginReads':plugin_reads}
	    else:
	        print(json.dumps({'id':request['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':request['id'],'result':result}), flush=True)
	"""#
}
