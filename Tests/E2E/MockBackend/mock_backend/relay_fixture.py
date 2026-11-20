"""Ephemeral relay host lifecycle without a relay network connection."""

import os
from pathlib import Path
import threading
import time

from .transport import ProtocolError


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
