import AppKit
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct SettingsUsagePageTests
{
	@Test(
		.timeLimit(.minutes(1)),
		arguments: ["valid", "unavailable", "expired", "account_changed"]
	)
	func selectedResetRevalidatesCreditAndPreservesPartiallyAvailableMetadata(
		mode: String
	) async throws
	{
		let fixture = try await UsagePageFixture.make(mode: mode)
		defer
		{
			fixture.close()
		}
		await fixture.backend.start()
		#expect(fixture.backend.isConnected)
		try await AppKitTestIsolation.perform
		{
			_ = NSApplication.shared
			let page = SettingsUsagePage(backend: fixture.backend)
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
			window.orderFront(nil)
			defer
			{
				fixture.backend.onChange = nil
				if let sheet = window.attachedSheet
				{
					window.endSheet(
						sheet,
						returnCode: .alertFirstButtonReturn
					)
				}
				window.close()
			}
			page.refresh()
			let loading = try #require(page.operation)
			await loading.value
			#expect(page.operation == nil)
			#expect(page.message.isEmpty)
			let usage = try #require(descendants(page).compactMap
			{
				$0 as? SettingsUsageView
			}
			.first)
			#expect(labels(in: usage).contains("ChatGPT Pro"))
			#expect(labels(in: usage).contains("5% left"))
			if mode != "valid"
			{
				#expect(labels(in: usage)
					.contains
					{
						$0.contains("Token activity could not be loaded")
					})
				#expect(labels(in: usage).contains
				{
					$0.contains("Activity unavailable")
				})
			}
			if mode == "valid"
			{
				let analytics = try #require(descendants(usage).compactMap
				{
					$0 as? NSButton
				}
				.first
				{
					$0.title == "Analytics"
				})
				#expect(analytics.dispatchConfiguredAction())
				#expect(labels(in: usage).contains(Int64(123456).formatted()))
				let overview = try #require(descendants(usage).compactMap
				{
					$0 as? NSButton
				}
				.first
				{
					$0.title == "Overview"
				})
				#expect(overview.dispatchConfiguredAction())
			}

			let reset = try resetButton(
				for: "Second reset",
				in: usage
			)
			#expect(reset.isEnabled)
			#expect(reset.dispatchConfiguredAction())
			#expect(window.attachedSheet != nil)
			#expect(page.operation == nil)
			let mutation = try await confirmAndCaptureOperation(
				in: window,
				page: page,
				backend: fixture.backend
			)
			await mutation.value
			#expect(page.operation == nil)
			let counts = try await fixture.backend.perform(
				"test/counts",
				params: [:]
			)
			if mode == "valid"
			{
				#expect(page.message.isEmpty)
				#expect(counts["consumedIDs"] as? [String] == ["credit-b"])
				let keys = try #require(counts["idempotencyKeys"] as? [String])
				#expect(keys.count == 1)
				#expect(UUID(uuidString: try #require(keys.first)) != nil)
				#expect(counts["rateReads"] as? Int == 3)
				#expect(counts["accountReads"] as? Int == 2)
				#expect(counts["activityReads"] as? Int == 2)
				#expect(labels(in: usage).contains("100% left"))
				#expect(labels(in: usage)
					.contains
					{
						$0.contains("Your eligible usage limits were reset.")
					})
				#expect(!labels(in: usage).contains
				{
					$0.contains("Reset result: reset")
				})
			}
			else
			{
				#expect(page.message.contains(mode == "account_changed"
						? "The account changed" : "This usage reset is no longer available"))
				#expect(counts["consumedIDs"] as? [String] == [])
				#expect(counts["idempotencyKeys"] as? [String] == [])
				#expect(counts["rateReads"] as? Int == 2)
				#expect(counts["accountReads"] as? Int == 1)
				#expect(counts["activityReads"] as? Int == 1)
				#expect(labels(in: usage).contains("ChatGPT Pro"))
				#expect(labels(in: usage).contains("5% left"))
			}
		}
	}

	private func confirmAndCaptureOperation(
		in window: NSWindow,
		page: SettingsUsagePage,
		backend: SettingsBackend
	) async throws
		-> Task<Void, Never>
	{
		let sheet = try #require(window.attachedSheet)
		return await withCheckedContinuation
		{
			continuation in
			backend.onChange =
			{
				[weak page, weak backend] in
				guard let operation = page?.operation
				else
				{
					return
				}
				backend?.onChange = nil
				continuation.resume(returning: operation)
			}
			window.endSheet(
				sheet,
				returnCode: .alertSecondButtonReturn
			)
		}
	}

	private func resetButton(
		for title: String,
		in view: NSView
	) throws -> NSButton
	{
		let label = try #require(descendants(view).compactMap
		{
			$0 as? NSTextField
		}
		.first
		{
			$0.stringValue == title
		})
		var container = label.superview
		while let current = container, current !== view
		{
			if let button = descendants(current).compactMap(
				{
					$0 as? NSButton
				}
			)
			.first(where:
				{
					$0.title == "Use reset"
				})
			{
				return button
			}
			container = current.superview
		}
		throw AppServerError.protocolError("The selected reset has no action button.")
	}

	private func labels(in view: NSView) -> [String]
	{
		descendants(view).compactMap
		{
			($0 as? NSTextField)?.stringValue
		}
	}

	private func descendants(_ view: NSView) -> [NSView]
	{
		[view] + view.subviews.flatMap(descendants)
	}
}

@MainActor
private struct UsagePageFixture
{
	let directory: URL
	let backend: SettingsBackend

	func close()
	{
		backend.stop()
		try? FileManager.default.removeItem(at: directory)
	}

	static func make(mode: String) async throws -> UsagePageFixture
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		do
		{
			let executable = try await AppServerTestExecutable.mockExecutable(
				in: directory,
				script: script
					.replacingOccurrences(
						of: "TEST_MODE",
						with: mode
					)
			)
			return UsagePageFixture(
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
	import sys, json, time, uuid
	if '--version' in sys.argv:
	    print('codex-cli 0.163.0')
	    sys.exit(0)
	mode = 'TEST_MODE'
	rate_reads, account_reads, activity_reads = 0, 0, 0
	consumed_ids, idempotency_keys = [], []
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
	    elif method == 'account/rateLimits/read':
	        rate_reads += 1
	        now = int(time.time())
	        credits = [{'id':'credit-a','resetType':'codexRateLimits','status':'available',
	            'grantedAt':now-3600,'expiresAt':now+86400,'title':'First reset'},
	            {'id':'credit-b','resetType':'codexRateLimits','status':'available',
	            'grantedAt':now-3600,'expiresAt':now+86400,'title':'Second reset'}]
	        if rate_reads >= 2 and mode == 'unavailable': credits[1]['status'] = 'redeemed'
	        if rate_reads >= 2 and mode == 'expired': credits[1]['expiresAt'] = now-60
	        if consumed_ids: credits[1]['status'] = 'redeemed'
	        available = sum(c['status']=='available' and c['expiresAt']>now for c in credits)
	        result = {'accountId':'fixture-account','rateLimits':{
	            'primary':{'usedPercent':0 if consumed_ids else 95,
	                'windowDurationMins':300,'resetsAt':now+3600},
	            'secondary':{'usedPercent':20,'windowDurationMins':10080,'resetsAt':now+86400}},
	            'rateLimitResetCredits':{'availableCount':available,'credits':credits}}
	        if rate_reads >= 2 and mode == 'account_changed': result['accountId'] = 'other-account'
	    elif method == 'account/read':
	        account_reads += 1
	        assert params == {'refreshToken':False}
	        result = {'account':{'type':'chatgpt','planType':'pro'},'requiresOpenaiAuth':True}
	    elif method == 'account/usage/read':
	        activity_reads += 1
	        if mode != 'valid':
	            print(json.dumps({'id':request['id'],'error':{
	                'code':-32000,'message':'Activity unavailable'}}), flush=True)
	            continue
	        result = {'summary':{'lifetimeTokens':123456},'dailyUsageBuckets':[]}
	    elif method == 'account/rateLimitResetCredit/consume':
	        assert rate_reads >= 2
	        uuid.UUID(params['idempotencyKey'])
	        consumed_ids.append(params['creditId'])
	        idempotency_keys.append(params['idempotencyKey'])
	        result = {'outcome':'reset'}
	    elif method == 'test/counts':
	        result = {'rateReads':rate_reads,'accountReads':account_reads,
	            'activityReads':activity_reads,
	            'consumedIDs':consumed_ids,'idempotencyKeys':idempotency_keys}
	    else:
	        print(json.dumps({'id':request['id'],'error':{
	            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
	        continue
	    print(json.dumps({'id':request['id'],'result':result}), flush=True)
	"""#
}
