"""Realtime app-server events for an isolated pair of synthetic media peers."""

import base64
import json
import os
import struct
import threading
import time
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
    if method == 'thread/realtime/start' and params.get('transport') == {'type': 'websocket'}:
        if not server.scenario.get('desktopVoiceReconnect') or server.voice_call or not server.voice_initial_retired:
            raise ProtocolError(-32602, 'WebSocket started before the previous voice session closed')
        session = str(UUID(params['realtimeSessionId'], version=4))
        if params.get('voice') != 'cedar' or params.get('version') != 'v3':
            raise ProtocolError(-32602, 'Fallback changed the captured voice')
        server.voice_call = (thread, session)
        server.voice_transport = 'websocket'
        server.voice_pcm_sent = False
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
        server.voice_transport = 'webrtc'
        if server.scenario.get('desktopVoiceReconnect') and not server.voice_initial_retired:
            server.transport.event('thread/realtime/error', {'threadId': thread, 'message': 'Fixture startup loss'})
            return {}
        server.transport.event('thread/realtime/sdp', {'threadId': 'history-second', 'sdp': exchange['answer']})
        server.transport.event('thread/realtime/sdp', {'threadId': thread, 'sdp': exchange['answer']})
        server.transport.event('thread/realtime/started', {
            'threadId': thread, 'realtimeSessionId': session, 'version': 'v3'})
        if server.scenario.get('desktopVoiceHandoff'):
            if params.get('clientManagedHandoffs') is not False:
                raise ProtocolError(-32602, 'The voice call did not delegate handoffs to Codex')
            background = threading.Thread(target=handoff, args=(server, thread), daemon=True)
            server.actions.append(background.start)
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
    if method == 'thread/realtime/appendAudio' and server.voice_transport == 'websocket':
        audio = params.get('audio', {})
        pcm = base64.b64decode(audio.get('data', ''), validate=True)
        if (audio.get('sampleRate') != 24000 or audio.get('numChannels') != 1
                or len(pcm) != audio.get('samplesPerChannel', 0) * 2 or not any(pcm)):
            raise ProtocolError(-32602, 'Invalid voice microphone audio')
        if not server.voice_pcm_sent:
            server.voice_pcm_sent = True
            server.transport.event('thread/realtime/outputAudio/delta', {'threadId': thread, 'audio': audio})
        return {}
    if method == 'thread/realtime/appendText':
        if not params.get('text') or params.get('role') != 'user':
            raise ProtocolError(-32602, 'Unexpected realtime input')
        if server.scenario.get('desktopVoiceReconnect') and params['text'] == 'Drop this call':
            if server.voice_transport != 'websocket' or not server.voice_pcm_sent:
                raise ProtocolError(-32602, 'The live dropout fixture did not start from duplex audio')
            profile = Path(os.environ['CODEX_GUI_QA_VOICE_SETTINGS'])
            profile.write_text('{"voice":"marin","version":2}', encoding='utf-8')
            server.actions.append(lambda: close_voice(server, thread, 'fixture-drop'))
        return {}
    if method == 'thread/realtime/stop':
        if server.scenario.get('desktopVoiceReconnect') and not standalone and not server.voice_initial_retired:
            server.transport.event('thread/realtime/closed', {'threadId': 'history-second', 'reason': 'requested'})
            elapsed = threading.Timer(0.65, lambda: close_voice(server, thread, 'fixture-startup-closed'))
            elapsed.daemon = True
            server.actions.append(elapsed.start)
        else:
            close_voice(server, thread, 'requested')
        return {}
    raise ProtocolError(-32601, 'Unexpected realtime request')


def close_voice(server, thread, reason):
    with server.lock:
        if server.voice_call and server.voice_call[0] == thread:
            server.voice_call = None
            if reason == 'fixture-startup-closed':
                server.voice_initial_retired = True
            server.transport.event('thread/realtime/closed', {'threadId': thread, 'reason': reason})


def handoff(server, thread):
    signal = Path(os.environ['CODEX_GUI_QA_HANDOFF_TRIGGER'])
    deadline = time.monotonic() + 12
    while not signal.is_file():
        if time.monotonic() > deadline:
            return
        time.sleep(0.025)
    with server.lock:
        if not server.voice_call or server.voice_call[0] != thread:
            return
        owner = server.thread(thread)
        server.transport.trace({'direction': 'voice-handoff', 'threadId': thread, 'cwd': owner['cwd']})
        server.start({'threadId': thread, 'input': [{'type': 'text', 'text': 'Inspect the approved checkout.'}]})
        server.after_reply()
