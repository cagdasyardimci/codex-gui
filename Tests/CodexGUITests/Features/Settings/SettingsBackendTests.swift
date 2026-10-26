import AppKit
import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsBackendTests
{
	@Test func queuedWritesUseRefreshedVersionsAndReplaceEntireOriginTables() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "success")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		#expect(fixture.backend.isConnected)
		#expect(fixture.backend.value("model") as? String == "initial")
		#expect(fixture.backend
			.requirements["allowedApprovalPolicies"] as? [String] == ["on-request"])

		let first = Task
		{
			await fixture.backend.write([
				"model": "updated",
				"browser_use.origins": ["https://example.com": ["access": "allow"]],
			])
		}
		let second = Task
		{
			await fixture.backend.write(["model": "updated"])
		}
		await first.value
		await second.value
		let counts = try await fixture.backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["writes"] as? Int == 2)
		#expect(counts["reads"] as? Int == 3)
		#expect(fixture.backend.value("model") as? String == "updated")
		let origins = fixture.backend.value("browser_use.origins") as? [String: Any]
		#expect(origins?.keys.sorted() == ["https://example.com"])
		#expect(!fixture.backend.isBusy)
	}

	@Test func rejectedWriteIsReadBackWithoutReplayAndRetainsError() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "reject")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		var saved = false
		fixture.backend.onDidSave =
		{
			_ in saved = true
		}
		let accepted = await fixture.backend.write(["model": "rejected"])
		#expect(!accepted)
		#expect(!saved)
		#expect(fixture.backend.status.contains("Managed setting cannot be changed"))
		#expect(fixture.backend.value("model") as? String == "initial")
		let counts = try await fixture.backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["writes"] as? Int == 1)
		#expect(counts["reads"] as? Int == 2)
		fixture.backend.stop()
		#expect(fixture.backend.config.isEmpty)
		#expect(!fixture.backend.isConnected)
		await #expect(throws: AppServerError.self)
		{
			_ = try await fixture.backend.perform(
				"test/counts",
				params: [:]
			)
		}
	}

	@Test(arguments: ["unknown_status", "missing_version"])
	func malformedWriteReceiptReadsBackWithoutPublishingSaveOrReplaying(mode: String) async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: mode)
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		try #require(fixture.backend.isConnected)
		var saves = 0
		fixture.backend.onDidSave =
		{
			_ in saves += 1
		}
		let accepted = await fixture.backend.write(["model": "updated"])
		#expect(!accepted)
		#expect(saves == 0)
		#expect(fixture.backend.status.contains("invalid settings write result"))
		#expect(fixture.backend.value("model") as? String == "updated")
		let counts = try await fixture.backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["writes"] as? Int == 1)
		#expect(counts["reads"] as? Int == 2)
		#expect(!fixture.backend.isBusy)
	}

	@Test func successfulOverriddenWriteDisplaysEffectiveValue() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "overridden")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		var effectiveAtSave: String?
		fixture.backend.onDidSave =
		{
			[weak backend = fixture.backend] _ in
			effectiveAtSave = backend?.value("model") as? String
		}
		let accepted = await fixture.backend.write(["model": "requested"])
		#expect(accepted)
		#expect(effectiveAtSave == "initial")
		#expect(fixture.backend.value("model") as? String == "initial")
		#expect(fixture.backend.status.contains("higher-priority configuration overrides"))
	}
	@Test func featureCatalogResolvesDefaultsAcrossPagesAndOverridesExplicitValues() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "success")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		#expect(fixture.backend.value("features.local_thread_store_compression") == nil)
		#expect(fixture.backend.featureEnabled("local_thread_store_compression") == true)
		#expect(fixture.backend.featureEnabled("browser_use_full_cdp_access") == false)
		#expect(fixture.backend.featureEnabled("explicit_flag") == true)
		#expect(fixture.backend.featureEnabled("not_advertised") == nil)
		#expect(fixture.backend.featureStatus.isEmpty)
		let counts = try await fixture.backend.perform(
			"test/counts",
			params: [:]
		)
		#expect(counts["featureReads"] as? Int == 2)
		fixture.backend.stop()
		#expect(fixture.backend.featureEnabled("local_thread_store_compression") == nil)
		#expect(fixture.backend.featureStatus.isEmpty)
	}

	@Test(.timeLimit(.minutes(1)))
	func browserSwitchWritesBrowserUseFeature() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "success")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		let page = SettingsBrowserPage(backend: fixture.backend)
		let browser = page.descendants.compactMap
		{
			$0 as? RemoteConnectionsSwitch
		}.first
		{
			$0.accessibilityLabel() == "Browser"
		}
		let control = try #require(browser)
		#expect(control.isEnabled)
		await withCheckedContinuation
		{
			continuation in
			fixture.backend.onDidSave =
			{
				_ in continuation.resume()
			}
			control.state = .on
			#expect(control.sendAction(
				control.action,
				to: control.target
			))
		}
		#expect(fixture.backend.value("features.browser_use") as? Bool == true)
	}

	@Test func siteSettingsManageRevealsPermissionControls() async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: "success")
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		let page = SettingsBrowserPage(backend: fixture.backend)
		#expect(!page.descendants.contains
		{
			$0 is SettingsBrowserPermissionsTable
		})
		let manage = try #require(page.descendants.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Manage"
		})
		#expect(manage.sendAction(
			manage.action,
			to: manage.target
		))
		#expect(page.descendants.contains
		{
			$0 is SettingsBrowserPermissionsTable
		})
		let done = try #require(page.descendants.compactMap
		{
			$0 as? NSButton
		}.first
		{
			$0.title == "Done"
		})
		#expect(done.sendAction(
			done.action,
			to: done.target
		))
		#expect(!page.descendants.contains
		{
			$0 is SettingsBrowserPermissionsTable
		})
	}

	@Test(arguments: ["repeated_cursor", "catalog_unavailable"])
	func featureCatalogFailurePreservesConfigWritesAndExplicitFallback(mode: String) async throws
	{
		let fixture = try await SettingsBackendFixture.make(mode: mode)
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		#expect(fixture.backend.status.isEmpty)
		#expect(!fixture.backend.featureStatus.isEmpty)
		#expect(fixture.backend.featureEnabled("local_thread_store_compression") == nil)
		#expect(fixture.backend.featureEnabled("explicit_flag") == false)
		if mode == "repeated_cursor"
		{
			#expect(fixture.backend.featureStatus.contains("repeated the feature catalog cursor"))
		}
		let accepted = await fixture.backend.write(["model": "updated"])
		#expect(accepted)
		#expect(fixture.backend.value("model") as? String == "updated")
		#expect(!fixture.backend.featureStatus.isEmpty)
	}

}

@MainActor
private extension NSView
{
	var descendants: [NSView]
	{
		subviews.flatMap
		{
			[$0] + $0.descendants
		}
	}
}

@MainActor
private struct SettingsBackendFixture
{
	let directory: URL
	let backend: SettingsBackend

	func close()
	{
		backend.stop()
		try? FileManager.default.removeItem(at: directory)
	}

	static func make(mode: String) async throws -> SettingsBackendFixture
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		do
		{
			let executable = try await AppServerTestExecutable.mockExecutable(
				in: directory,
				script: script.replacingOccurrences(
					of: "TEST_MODE",
					with: mode
				)
			)
			return SettingsBackendFixture(
				directory: directory,
				backend: SettingsBackend(server: AppServer(
					executableOverride: executable,
					requestTimeout: .seconds(3)
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
	mode = 'TEST_MODE'
	config = {'model':'initial', 'features':{'explicit_flag':False},
	    'browser_use':{'origins':{'https://old.com':{'access':'deny'}}}}
	version, writes, reads, feature_reads = 1, 0, 0, 0
	for line in sys.stdin:
	    message = json.loads(line)
	    method, params = message.get('method'), message.get('params', {})
	    if method is None or method == 'initialized': continue
	    if method == 'initialize': result = {'userAgent':'mock'}
	    elif method == 'config/read':
	        assert params == {'includeLayers':True}
	        reads += 1
	        result = {'config':config, 'origins':{}, 'layers':[
	            {'name':{'type':'user','file':'/tmp/config.toml','profile':'named'},
	             'config':{},'version':'not-the-base-version'},
	            {'name':{'type':'user','file':'/tmp/config.toml'},
	             'config':config,'version':str(version)}]}
	    elif method == 'configRequirements/read':
	        result = {'requirements':{'allowedApprovalPolicies':['on-request']}}
	    elif method == 'experimentalFeature/list':
	        feature_reads += 1
	        assert params['limit'] == 100
	        if mode == 'catalog_unavailable':
	            print(json.dumps({'id':message['id'],'error':{
	                'code':-32601,'message':'Feature catalog unavailable'}}), flush=True)
	            continue
	        if 'cursor' not in params:
	            result = {'data':[{'name':'local_thread_store_compression','enabled':True}],
	                      'nextCursor':'page2'}
	        else:
	            assert params['cursor'] == 'page2'
	            result = {'data':[{'name':'browser_use','enabled':False},
	                              {'name':'browser_use_full_cdp_access','enabled':False},
	                              {'name':'explicit_flag','enabled':True}],
	                      'nextCursor':'page2' if mode == 'repeated_cursor' else None}
	    elif method == 'config/batchWrite':
	        writes += 1
	        assert params['expectedVersion'] == str(version)
	        assert params['reloadUserConfig'] is True
	        assert 'filePath' not in params
	        assert all(edit['mergeStrategy'] == 'replace' for edit in params['edits'])
	        if mode == 'reject':
	            print(json.dumps({'id':message['id'],'error':{
	                'code':-32000,'message':'Managed setting cannot be changed'}}), flush=True)
	            continue
	        if mode != 'overridden':
	            for edit in params['edits']:
	                path = edit['keyPath'].split('.')
	                parent = config
	                for key in path[:-1]: parent = parent.setdefault(key,{})
	                parent[path[-1]] = edit['value']
	        version += 1
	        result = {'status':'okOverridden' if mode == 'overridden' else 'ok',
	                  'filePath':'/tmp/config.toml','version':str(version)}
	        if mode == 'unknown_status': result['status'] = 'futureStatus'
	        if mode == 'missing_version': result.pop('version')
	    elif method == 'test/counts':
	        result = {'reads':reads,'writes':writes,'featureReads':feature_reads}
	    else:
	        print(json.dumps({'id':message['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':message['id'],'result':result}), flush=True)
	"""#
}
