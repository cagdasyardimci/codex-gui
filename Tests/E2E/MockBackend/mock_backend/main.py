"""Executable entry point. Stdout is reserved exclusively for protocol messages."""
import argparse
import json
import os
import sys
from pathlib import Path

from . import scenarios
from .server import Server
from .state import State
from .transport import ProtocolError, Transport


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', action='store_true')
    parser.add_argument('command', nargs='?', choices=['app-server'])
    parser.add_argument('--stdio', action='store_true')
    parser.add_argument('--scenario', default=None)
    args = parser.parse_args()
    if args.version:
        print('structured-qa-fixture 0.153.2')
        return 0
    if args.command != 'app-server' or not args.stdio:
        parser.error('Use app-server --stdio')
    state_path = os.environ.get('CODEX_GUI_QA_STATE')
    initial = json.loads(Path(state_path).read_text()) if state_path and Path(state_path).exists() else {}
    name = args.scenario or os.environ.get('CODEX_GUI_QA_SCENARIO') or initial.get('scenario', 'streaming')
    try:
        scenario = scenarios.load(name)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    transport = Transport(os.environ.get('CODEX_GUI_QA_TRACE'))
    server = Server(scenario, State(scenario, state_path), transport)
    transport.trace({'direction': 'fixture', 'scenario': name, 'modelCalls': False})
    try:
        for line in sys.stdin:
            identity = None
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or not isinstance(request.get('method'), str):
                    raise ProtocolError(-32600, 'Invalid request')
                identity = request.get('id')
                params = request.get('params', {})
                if not isinstance(params, dict):
                    raise ProtocolError(-32602, 'Params must be an object')
                record = {'direction': 'request', 'method': request['method'], 'id': identity, 'params': params, **params}
                if request['method'] in ('turn/start', 'turn/interrupt'):
                    record['resolvedCwd'] = server.thread(params.get('threadId')).get('cwd', '')
                transport.trace(record)
                if 'id' not in request:
                    if request['method'] != 'initialized':
                        print('Ignored notification: ' + request['method'], file=sys.stderr, flush=True)
                    continue
                result = server.handle(request['method'], params)
                transport.reply(identity, result=result)
                server.after_reply()
            except json.JSONDecodeError:
                transport.reply(None, error={'code': -32700, 'message': 'Malformed JSON'})
            except ProtocolError as error:
                transport.reply(identity, error={'code': error.code, 'message': str(error)})
            except (KeyError, TypeError, ValueError) as error:
                transport.reply(identity, error={'code': -32602, 'message': str(error)})
    except BrokenPipeError:
        pass
    finally:
        server.close()
    return 1 if server.failure else 0
