import Foundation
import Testing

@testable import CodexGUI

@MainActor
@Suite
struct AppServerRemoteAccessTests
{
	@Test func remoteAccessRequestsPreserveSessionEnablementPairingAndDeviceIdentity() async throws
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
			status = {'status':'disabled','serverName':'Test Mac',
			          'installationId':'installation','environmentId':'environment'}
			revoked = False
			def send(value): print(json.dumps(value), flush=True)
			for line in sys.stdin:
			    message = json.loads(line)
			    method = message.get('method')
			    params = message.get('params', {})
			    result = {}
			    if method is None or method == 'initialized': continue
			    if method == 'initialize': result = {'userAgent':'mock'}
			    elif method in ('remoteControl/enable', 'remoteControl/disable'):
			        assert params == {'ephemeral':True}, params
			        status['status'] = 'connecting' if method.endswith('/enable') else 'disabled'
			        result = dict(status)
			    elif method == 'remoteControl/status/read': result = status
			    elif method == 'remoteControl/pairing/start':
			        assert params == {'manualCode':True}, params
			        result = {'pairingCode':'secret-code','manualPairingCode':'ABCD-EFGH',
			                  'environmentId':'environment','expiresAt':2000000000}
			    elif method == 'remoteControl/pairing/status':
			        assert params == {'pairingCode':'secret-code'}, params
			        result = {'claimed':True}
			    elif method == 'remoteControl/client/list':
			        if params['environmentId'] == 'repeat':
			            send({'id':message['id'],'result':{'data':[],'nextCursor':'same'}})
			            continue
			        assert params['environmentId'] == 'environment', params
			        assert params['limit'] == 100, params
			        if revoked:
			            result = {'data':[{'clientId':'one'}],'nextCursor':None}
			        elif params.get('cursor'):
			            assert params['cursor'] == 'next', params
			            result = {'data':[{'clientId':'one'},{'clientId':'two'}],'nextCursor':None}
			        else: result = {'data':[{'clientId':'one'}],'nextCursor':'next'}
			    elif method == 'remoteControl/client/revoke':
			        assert params == {'environmentId':'environment','clientId':'two'}, params
			        revoked = True
			    else:
			        send({'id':message['id'],'error':{'code':-32601,
			              'message':'Unexpected method: '+str(method)}})
			        continue
			    send({'id':message['id'],'result':result})
			    if method == 'remoteControl/enable':
			        status['status'] = 'connected'
			        send({'method':'remoteControl/status/changed','params':status})
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
		var notifications: [RemoteControlStatus] = []
		server.onEvent =
		{
			if case .remoteControlStatusChanged(let status) = $0
			{
				notifications.append(status)
			}
		}
		try await server.connect()
		#expect(try await server.remoteControlStatus().status == .disabled)
		#expect(try await server.setRemoteControlEnabled(true).status == .connecting)
		#expect(try await server.remoteControlStatus().status == .connected)
		#expect(notifications.last?.status == .connected)
		let pairing = try await server.startRemoteControlPairing()
		#expect(pairing.expiresAt == 2_000_000_000)
		#expect(pairing.manualPairingCode == "ABCD-EFGH")
		#expect(try await server.remoteControlPairingClaimed(pairing))
		let clients = try await server.remoteControlClients(environmentID: "environment")
		#expect(clients.map(\.clientId) == ["one", "two"])
		do
		{
			_ = try await server.remoteControlClients(environmentID: "repeat")
			Issue.record("Expected the repeated cursor to be rejected")
		}
		catch AppServerError.protocolError(let message)
		{
			#expect(message.contains("repeated"))
		}
		try await server.revokeRemoteControlClient(
			environmentID: "environment",
			clientID: "two"
		)
		#expect(try await server.remoteControlClients(environmentID: "environment")
			.map(\.clientId) == ["one"])
		#expect(try await server.setRemoteControlEnabled(false).status == .disabled)
	}

	@Test func malformedPairingDoesNotExposeReturnedSecrets() throws
	{
		let server = AppServer()
		let response: [String: Any] = [
			"pairingCode": "sensitive-secret",
			"manualPairingCode": ["secret": "sensitive-secret"],
			"environmentId": "environment",
			"expiresAt": 1000,
		]
		do
		{
			let _: RemoteControlPairing = try server.decodeRemoteControl(response)
			Issue.record("Expected malformed pairing to fail")
		}
		catch
		{
			#expect(!error.localizedDescription.contains("sensitive-secret"))
		}
		let safe = BackendDiagnosticsBuffer.displaySafeText(
			#"{"pairing_code":"one", "manualPairingCode":"two", "remote_control_token":"three"}"#
		)
		#expect(!safe.contains("\"one\""))
		#expect(!safe.contains("\"two\""))
		#expect(!safe.contains("\"three\""))
	}
}
