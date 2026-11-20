"""Realtime app-server events for an isolated pair of synthetic media peers."""

import json
import os
from pathlib import Path
from uuid import UUID

from .transport import ProtocolError


def voice_request(server, method, params):
    thread = server.thread(params.get('threadId'))['id']
    if method == 'thread/realtime/start':
        exchange = json.loads(Path(os.environ['CODEX_GUI_QA_VOICE_EXCHANGE']).read_text(encoding='utf-8'))
        session = str(UUID(params['realtimeSessionId'], version=4))
        if (server.voice_call is not None or session != params['realtimeSessionId']
                or params.get('version') != 'v3' or params.get('outputModality') != 'audio'
                or params.get('transport') != {'type': 'webrtc', 'sdp': exchange['offer']}):
            raise ProtocolError(-32602, 'Unexpected voice offer')
        server.voice_call = (thread, session)
        server.transport.event('thread/realtime/sdp', {'threadId': 'history-second', 'sdp': exchange['answer']})
        server.transport.event('thread/realtime/sdp', {'threadId': thread, 'sdp': exchange['answer']})
        server.transport.event('thread/realtime/started', {
            'threadId': thread, 'realtimeSessionId': session, 'version': 'v3'})
        return {}
    if not server.voice_call or server.voice_call[0] != thread:
        raise ProtocolError(-32602, 'Realtime request was routed to the wrong chat')
    if method == 'thread/realtime/appendText':
        if not params.get('text') or params.get('role') != 'user':
            raise ProtocolError(-32602, 'Unexpected realtime input')
        return {}
    if method == 'thread/realtime/stop':
        server.voice_call = None
        server.transport.event('thread/realtime/closed', {'threadId': thread, 'reason': 'requested'})
        return {}
    raise ProtocolError(-32601, 'Unexpected realtime request')
