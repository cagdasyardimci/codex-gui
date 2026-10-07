"""Serialized JSONL stdout and independent diagnostic tracing."""
import json
import sys
import threading
import time
from pathlib import Path


class ProtocolError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


class Transport:
    def __init__(self, trace_path=None):
        self.lock = threading.RLock()
        self.trace_path = Path(trace_path) if trace_path else None
        if self.trace_path:
            self.trace_path.parent.mkdir(parents=True, exist_ok=True)

    def trace(self, record):
        if self.trace_path:
            with self.lock, self.trace_path.open('a') as output:
                output.write(json.dumps({'time': time.time(), **record}, ensure_ascii=True) + '\n')

    def send(self, message):
        with self.lock:
            sys.stdout.write(json.dumps(message, ensure_ascii=True) + '\n')
            sys.stdout.flush()

    def reply(self, identity, result=None, error=None):
        message = {'id': identity}
        message['error' if error else 'result'] = error if error else result
        self.trace({'direction': 'response', **message})
        self.send(message)

    def event(self, method, params):
        turn = params.get('turn', {})
        self.trace({'direction': 'event', 'method': method, **params,
                    'turnId': params.get('turnId', turn.get('id')),
                    'status': turn.get('status')})
        self.send({'method': method, 'params': params})
