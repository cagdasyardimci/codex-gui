import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerAccountTests
{
	@Test func accountReadPreservesReportedIdentityAndPlanAndLogoutUsesServerRequest() async throws
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
			import sys, json
			if '--version' in sys.argv:
			    print('codex-cli 0.163.0')
			    sys.exit(0)
			logged_out = False
			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    if method is None or method == 'initialized': continue
			    if method == 'initialize': result = {'userAgent':'mock'}
			    elif method == 'account/read':
			        assert message['params'] == {'refreshToken':False}
			        account = None if logged_out else {
			            'type':'chatgpt','email':'member@example.com','planType':'pro'}
			        result = {'account':account,'requiresOpenaiAuth':True}
			    elif method == 'account/logout':
			        assert 'params' not in message
			        logged_out = True
			        result = {}
			    else:
			        print(json.dumps({'id':message['id'],'error':{
			            'code':-32601,'message':'Unexpected method: '+str(method)}}), flush=True)
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
		let account = try await server.accountStatus()
		#expect(account.type == "chatgpt")
		#expect(account.email == "member@example.com")
		#expect(account.planType == "pro")
		try await server.logout()
		let loggedOut = try await server.accountStatus()
		#expect(loggedOut.type == nil)
		#expect(loggedOut.email == nil)
		#expect(loggedOut.planType == nil)
		#expect(loggedOut.requiresOpenAIAuth)
	}
}
