"""Realtime app-server events for an isolated pair of synthetic media peers."""

import base64
import json
import os
import struct
from pathlib import Path
from uuid import UUID

from .transport import ProtocolError

VOICES = ('marin', 'cedar', 'rindo')


def voice_config(server, method, params):
    profile = Path(os.environ['CODEX_GUI_QA_VOICE_SETTINGS'])
    value = json.loads(profile.read_text(encoding='utf-8'))
    file = str(Path(os.environ['CODEX_HOME']) / 'config.toml')
    if method == 'config/read':
        return {'config': {**server.state.data['config'], 'realtime': {'voice': value['voice']}},
                'origins': {}, 'layers': [{'name': {'type': 'user', 'file': file}, 'version': str(value['version'])}]}
    if (params.get('keyPath') != 'realtime.voice' or params.get('filePath') != file
            or params.get('expectedVersion') != str(value['version']) or params.get('value') not in (*VOICES, None)):
        raise ProtocolError(-32602, 'Unexpected voice configuration write')
    next_value = {'voice': params['value'], 'version': value['version'] + 1}
    temporary = profile.with_suffix('.tmp')
    temporary.write_text(json.dumps(next_value), encoding='utf-8')
    os.replace(temporary, profile)
    return {'filePath': file, 'version': str(next_value['version']), 'status': 'ok'}


def voice_request(server, method, params):
    if method == 'thread/realtime/listVoices':
        return {'voices': {'v3': VOICES, 'v1': VOICES, 'v2': VOICES,
                           'defaultV1': 'marin', 'defaultV2': 'marin'}}
    thread = server.thread(params.get('threadId'))['id']
    standalone = server.client_name == 'codex_gui_speech'
    if method == 'thread/realtime/start' and standalone:
        session = str(UUID(params['realtimeSessionId'], version=4))
        if (not thread.startswith('voice-sample-') or params.get('voice') not in VOICES or
                params.get('version') != 'v3' or params.get('transport') != {'type': 'websocket'} or
                params.get('includeStartupContext') is not False or not params.get('clientManagedHandoffs')):
            raise ProtocolError(-32602, 'Unexpected standalone speech start')
        server.voice_call = (thread, session)
        server.transport.event('thread/realtime/started', {
            'threadId': thread, 'realtimeSessionId': session, 'version': 'v3'})
        return {}
    if method == 'thread/realtime/start':
        exchange = json.loads(Path(os.environ['CODEX_GUI_QA_VOICE_EXCHANGE']).read_text(encoding='utf-8'))
        session = str(UUID(params['realtimeSessionId'], version=4))
        if (server.voice_call is not None or session != params['realtimeSessionId']
                or params.get('version') != 'v3' or params.get('outputModality') != 'audio'
                or params.get('voice') not in VOICES
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
    if method == 'thread/realtime/appendSpeech' and standalone:
        if not params.get('text'):
            raise ProtocolError(-32602, 'Speech sample must have text')
        frames = 16000
        waveform = struct.pack('<' + 'h' * frames, *([1000, -1000, 250, -250] * (frames // 4)))
        server.transport.event('thread/realtime/outputAudio/delta', {'threadId': thread, 'audio': {
            'data': base64.b64encode(waveform).decode('ascii'), 'sampleRate': 8000,
            'numChannels': 1, 'samplesPerChannel': frames,
        }})
        return {}
    if method == 'thread/realtime/appendText':
        if not params.get('text') or params.get('role') != 'user':
            raise ProtocolError(-32602, 'Unexpected realtime input')
        return {}
    if method == 'thread/realtime/stop':
        server.voice_call = None
        server.transport.event('thread/realtime/closed', {'threadId': thread, 'reason': 'requested'})
        return {}
    raise ProtocolError(-32601, 'Unexpected realtime request')
