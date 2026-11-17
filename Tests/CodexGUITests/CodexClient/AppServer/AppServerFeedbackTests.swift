import Foundation
import Testing

@testable import CodexGUI

@MainActor
struct AppServerFeedbackTests
{
	@Test(arguments: [
		"enabled",
		"disabled",
		"null",
		"malformed",
		"receipt",
		"upstream",
		"missing",
		"directory",
		"preflight"
	])
	func feedbackRequestsExcludeLogsAndPreserveReportScope(mode: String) async throws
	{
		let directory = try await AppServerTestExecutable.temporaryDirectory()
		defer
		{
			try? FileManager.default.removeItem(at: directory)
		}
		let executable = try await AppServerTestExecutable.mockExecutable(
			in: directory,
			script: #"""
		#!/usr/bin/env python3
		import json, os, sys
		if '--version' in sys.argv:
		    print('codex-cli 0.164.0')
		    sys.exit(0)
		mode = "\#(mode)"
		config_reads = 0
		uploads = []
		for line in sys.stdin:
		    message = json.loads(line)
		    method = message.get('method')
		    params = message.get('params', {})
		    if method in (None, 'initialized'): continue
		    result = {}
		    if method == 'initialize': result = {'userAgent':'mock'}
		    elif method == 'config/read':
		        assert params == {'includeLayers':False, 'cwd':os.path.dirname(__file__)}, params
		        config_reads += 1
		        if mode == 'preflight':
		            response = {'id':message['id'], 'error':{'code':-32600,
		                        'message':'Project configuration could not be read'}}
		            print(json.dumps(response), flush=True)
		            continue
		        feedback = None if mode == 'null' else {'enabled':mode != 'disabled'}
		        if mode == 'malformed': feedback = {'enabled':'false'}
		        result = {'config':{'feedback':feedback}}
		    elif method == 'feedback/upload':
		        assert params == {'classification':params['classification'], 'threadId':'chat',
		                          'includeLogs':False, 'tags':{'turn_id':'turn'}}, params
		        assert params['classification'] in ('good_result', 'bad_result'), params
		        assert mode not in ('disabled', 'malformed'), mode
		        uploads.append(params['classification'])
		        if mode in ('upstream', 'missing'):
		            error = ('Unknown method feedback/upload' if mode == 'missing'
		                     else 'Upstream request failed')
		            response = {'id':message['id'],'error':{'code':-32600,'message':error}}
		            print(json.dumps(response), flush=True)
		            continue
		        result = {} if mode == 'receipt' else {'threadId':'feedback-report'}
		    elif method == 'test/requests': result = {'uploads':uploads,'configReads':config_reads}
		    else:
		        print(json.dumps({'id':message['id'],'error':{'code':-32601,
		                         'message':'Unexpected method '+str(method)}}), flush=True)
		        continue
		    print(json.dumps({'id':message['id'],'result':result}), flush=True)
		"""#
		)
		let server = AppServer(
			executableOverride: executable,
			requestTimeout: .seconds(3)
		)
		defer
		{
			server.disconnect()
		}
		try await server.connect()
		let submission = ResultFeedbackSubmission(
			target: ResultFeedbackTarget(
				threadID: "chat",
				turnID: "turn"
			),
			rating: .bad
		)
		do
		{
			try await server.submitResultFeedback(
				submission,
				in: mode == "directory" ? directory.appendingPathComponent("absent") : directory
			)
			#expect(["enabled", "null"].contains(mode))
		}
		catch let failure as ResultFeedbackRequestFailure
		{
			#expect(!["enabled", "null"].contains(mode))
			#expect(failure.unavailable == ["disabled", "missing"].contains(mode))
			#expect(failure.failure.outcomeIsUncertain == ["receipt", "upstream"].contains(mode))
		}
		let requests = try await server.settingsRequest(
			"test/requests",
			params: [:]
		)
		#expect(requests["configReads"] as? Int == (mode == "directory" ? 0 : 1))
		#expect(requests["uploads"] as? [String] ==
			(["disabled", "malformed", "directory", "preflight"]
				.contains(mode) ? [] : ["bad_result"]))
		if mode == "enabled"
		{
			try await server.submitResultFeedback(
				ResultFeedbackSubmission(
					target: submission.target,
					rating: .good
				),
				in: directory
			)
			let next = try await server.settingsRequest(
				"test/requests",
				params: [:]
			)
			#expect(next["uploads"] as? [String] == ["bad_result", "good_result"])
		}
	}
}
