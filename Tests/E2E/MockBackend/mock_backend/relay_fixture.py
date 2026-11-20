"""Ephemeral relay host lifecycle without a relay network connection."""

import os
import json
from pathlib import Path
import threading
import time

from .transport import ProtocolError

PEER_THREAD = 'relay-mobile-history'
PEER_TURN = 'relay-mobile-turn'


def relay_host_request(server, method, params):
    status = getattr(server, 'relay_host_status', 'disabled')
    server.transport.trace({'direction': 'relay-host', 'method': method, 'cwd': os.getcwd(),
                            'process': os.getpid(), 'params': params})

    def response(phase):
        return {'status': phase, 'serverName': 'Fixture source', 'installationId': 'fixture-installation',
                'environmentId': f'fixture-environment-{os.getpid()}' if phase == 'connected' else None}

    def connected():
        time.sleep(0.2)
        with server.lock:
            if server.relay_host_status == 'connecting':
                server.relay_host_status = 'connected'
                server.transport.event('remoteControl/status/changed', response('connected'))

    if method == 'remoteControl/status/read':
        return response(status)
    if status == 'connected' and server.scenario.get('desktopRelayDevices'):
        if method in ('remoteControl/pairing/start', 'remoteControl/pairing/status',
                      'remoteControl/client/list', 'remoteControl/client/revoke'):
            return relay_devices_request(server, method, params, response(status)['environmentId'])
    if params != {'ephemeral': True}:
        raise ProtocolError(-32602, 'The desktop must keep relay enablement ephemeral')
    if method == 'remoteControl/disable':
        server.relay_host_status = 'disabled'
        server.transport.event('remoteControl/status/changed', response('disabled'))
        return response('disabled')
    if method == 'remoteControl/enable':
        conflict = Path(os.environ['CODEX_GUI_QA_RELAY_CONFLICT'])
        if conflict.exists():
            conflict.unlink()
            server.relay_host_status = 'errored'
            raise ProtocolError(409, 'Remote app server already online')
        server.relay_host_status = 'connecting'
        server.actions.append(lambda: threading.Thread(target=connected, daemon=True).start())
        return response('connecting')
    raise ProtocolError(-32601, 'Unsupported fixture relay request')


def relay_data():
    path = Path(os.environ['CODEX_GUI_QA_RELAY_DEVICES'])
    if path.exists():
        return json.loads(path.read_text(encoding='utf-8'))
    return {'pairings': 0, 'devices': [], 'peerTurn': None, 'failList': False}


def persist(data):
    path = Path(os.environ['CODEX_GUI_QA_RELAY_DEVICES'])
    temporary = path.with_name(f'{path.name}.{os.getpid()}.tmp')
    temporary.write_text(json.dumps(data), encoding='utf-8')
    os.replace(temporary, path)


def relay_devices_request(server, method, params, environment):
    data = relay_data()
    if method == 'remoteControl/pairing/start':
        if params != {'manualCode': True}:
            raise ProtocolError(-32602, 'Pairing needs a manual code')
        number = data['pairings'] + 1
        data['pairings'] = number
        persist(data)
        code = f'fixture:pairing/{number} + encoded'
        server.relay_pairing = (number, code, 0)
        return {'environmentId': environment, 'pairingCode': code, 'manualPairingCode': f'FIXTURE-{number:02d}',
                'expiresAt': int(time.time()) + (4 if number == 2 else 40)}
    if method == 'remoteControl/pairing/status':
        number, code, seen = server.relay_pairing
        if params != {'pairingCode': code}:
            raise ProtocolError(-32602, 'Unexpected pairing credential')
        server.relay_pairing = (number, code, seen + 1)
        if number in (3, 4) and seen >= 1:
            title = 'Fixture Phone' if number == 3 else 'Fixture Computer'
            device = {'clientId': f'fixture-device-{number}', 'displayName': title}
            if device not in data['devices']:
                data['devices'].append(device)
            if number == 3:
                data['peerTurn'] = 'inProgress'
                server.transport.trace({'direction': 'relay-peer-project', 'projectPath': os.getcwd(),
                                        'threadId': PEER_THREAD, 'clientId': device['clientId']})
            persist(data)
            return {'claimed': True}
        return {'claimed': False}
    if params.get('environmentId') != environment:
        raise ProtocolError(-32602, 'Relay device request targeted another environment')
    if method == 'remoteControl/client/list':
        if data['failList']:
            data['failList'] = False
            persist(data)
            raise ProtocolError(-32000, 'Fixture stale device list read')
        if params.get('cursor') == 'fixture-next-devices':
            return {'data': data['devices'][1:], 'nextCursor': None}
        return {'data': data['devices'][:1], 'nextCursor': 'fixture-next-devices' if len(data['devices']) > 1 else None}
    if method == 'remoteControl/client/revoke':
        if not any(device['clientId'] == params.get('clientId') for device in data['devices']):
            raise ProtocolError(-32602, 'Revocation was replayed or targeted another device')
        data['devices'] = [device for device in data['devices'] if device['clientId'] != params['clientId']]
        data['failList'] = True
        persist(data)
        return {}
    raise ProtocolError(-32601, 'Unsupported fixture devices request')


def sync_relay_thread(server, requested_cwd=None):
    if not Path.cwd().samefile(os.environ['CODEX_GUI_QA_RELAY_SOURCE']):
        return
    status = relay_data()['peerTurn']
    if status is None:
        return
    items = [{'id': 'relay-mobile-prompt', 'type': 'userMessage',
              'content': [{'type': 'text', 'text': 'Continue on the paired phone.'}]}]
    if status == 'completed':
        items.append({'id': 'relay-mobile-answer', 'type': 'agentMessage', 'text': 'The paired turn completed.'})
    turn = {'id': PEER_TURN, 'status': status, 'items': items}
    if status == 'inProgress':
        server.active.setdefault(PEER_THREAD, None)
    else:
        server.active.pop(PEER_THREAD, None)
    existing = next((thread for thread in server.state.threads if thread['id'] == PEER_THREAD), None)
    if isinstance(requested_cwd, list):
        requested_cwd = requested_cwd[0] if requested_cwd else None
    cwd = requested_cwd if requested_cwd and Path(requested_cwd).samefile(Path.cwd()) else os.getcwd()
    if existing is None:
        server.state.threads.append({'id': PEER_THREAD, 'name': 'Paired phone chat', 'cwd': cwd,
                                     'preview': items[0]['content'][0]['text'], 'archived': False, 'turns': [turn]})
    else:
        existing['turns'] = [turn]
        if requested_cwd:
            existing['cwd'] = cwd


def resume_relay_thread(server, thread):
    if thread['id'] != PEER_THREAD or relay_data()['peerTurn'] != 'inProgress':
        return

    def request():
        with server.lock:
            key = 'fixture-relay-approval'
            if relay_data()['peerTurn'] != 'inProgress' or key in server.command_approvals:
                return
            details = {'threadId': PEER_THREAD, 'turnId': PEER_TURN, 'itemId': 'fixture-relay-command',
                       'command': 'Inspect paired workspace', 'availableDecisions': ['accept', 'decline']}
            server.command_approvals[key] = {'threadId': PEER_THREAD, 'ready': threading.Event(), 'decision': None}
            server.transport.trace({'direction': 'relay-approval', 'process': os.getpid(), 'params': details})
            server.transport.send({'method': 'item/commandExecution/requestApproval', 'id': key, 'params': details})

    timer = threading.Timer(0.45, request)
    timer.daemon = True
    server.actions.append(timer.start)


def finish_relay_thread(server, decision):
    if decision != 'accept':
        return
    data = relay_data()
    data['peerTurn'] = 'completed'
    persist(data)
    sync_relay_thread(server)
    thread = server.thread(PEER_THREAD)
    server.transport.event('serverRequest/resolved', {'threadId': PEER_THREAD, 'requestId': 'fixture-relay-approval'})
    server.transport.event('item/completed', {'threadId': PEER_THREAD, 'turnId': PEER_TURN, 'item': thread['turns'][0]['items'][-1]})
    server.transport.event('turn/completed', {'threadId': PEER_THREAD, 'turn': thread['turns'][0]})
