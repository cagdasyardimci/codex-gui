#!/usr/bin/env python3
"""Verify installed app-server concurrency with a synthetic localhost Responses provider.

No remote model inference or authentication is used. Runtime homes and checkouts are
removed on exit; compact JSONL evidence and stderr remain in the printed directory.
"""

import argparse
import http.server
import json
import os
import pathlib
import queue
import shutil
import subprocess
import tempfile
import threading
import time


class EvidenceLog:
    def __init__(self, directory):
        self.path = directory / 'evidence.jsonl'
        self.lock = threading.Lock()

    def record(self, kind, data):
        entry = {'at': time.monotonic(), 'kind': kind, 'data': data}
        with self.lock:
            with self.path.open('a') as output:
                output.write(json.dumps(entry) + '\n')


class LocalResponsesProvider:
    """Hold each synthetic response until the concurrency checks release its owner."""

    def __init__(self, evidence):
        self.evidence = evidence
        self.accepted_owners = queue.Queue()
        self.release_events = {owner: threading.Event() for owner in ('alpha', 'beta')}
        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), ResponsesHandler)
        self.server.daemon_threads = True
        self.server.provider = self
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self):
        return f'http://127.0.0.1:{self.server.server_port}/v1'

    def start(self):
        self.worker.start()

    def close(self):
        for release_event in self.release_events.values():
            release_event.set()
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=3)


class ResponsesHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_arguments):
        pass

    def send_event(self, event):
        payload = f"event: {event['type']}\ndata: {json.dumps(event)}\n\n"
        self.wfile.write(payload.encode())
        self.wfile.flush()

    def do_POST(self):
        provider = self.server.provider
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        request = json.loads(body)
        request_text = json.dumps(request)
        if 'ALPHA_LOCAL_PROBE' in request_text:
            owner = 'alpha'
        elif 'BETA_LOCAL_PROBE' in request_text:
            owner = 'beta'
        else:
            owner = 'unknown'

        authorization_present = bool(self.headers.get('Authorization'))
        provider.evidence.record('local_model_request', {
            'owner': owner,
            'path': self.path,
            'model': request.get('model'),
            'authorization_present': authorization_present,
        })
        if authorization_present:
            raise RuntimeError('Synthetic probe unexpectedly received authentication')
        provider.accepted_owners.put(owner)

        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Connection', 'close')
        self.end_headers()
        try:
            self.send_event({'type': 'response.created', 'response': {'id': 'resp_' + owner}})
            release_event = provider.release_events.get(owner)
            if release_event is None or not release_event.wait(20):
                return
            self.send_completion(owner)
            provider.evidence.record('stub_released', {'owner': owner})
        except (BrokenPipeError, ConnectionResetError):
            provider.evidence.record('stub_client_disconnected', {'owner': owner})
        finally:
            self.close_connection = True

    def send_completion(self, owner):
        text = 'Synthetic ' + owner + ' completed'
        item = {
            'id': 'msg_' + owner,
            'type': 'message',
            'role': 'assistant',
            'content': [{'type': 'output_text', 'text': text, 'annotations': []}],
        }
        self.send_event({
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {**item, 'content': []},
        })
        self.send_event({
            'type': 'response.output_text.delta',
            'output_index': 0,
            'content_index': 0,
            'item_id': item['id'],
            'delta': text,
        })
        self.send_event({'type': 'response.output_item.done', 'output_index': 0, 'item': item})
        self.send_event({
            'type': 'response.completed',
            'response': {
                'id': 'resp_' + owner,
                'status': 'completed',
                'output': [item],
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
            },
        })


class AppServerClient:
    """Own one stdio process, request correlation, and bounded event observation."""

    def __init__(self, executable, environment, evidence, stderr):
        self.evidence = evidence
        self.messages = queue.Queue()
        self.history = []
        self.next_request_id = 0
        self.deadline = time.monotonic() + 60
        self.process = subprocess.Popen(
            [executable, 'app-server', '--listen', 'stdio://'],
            env=environment,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr,
            text=True,
        )
        self.reader = threading.Thread(target=self.read_messages, daemon=True)
        self.reader.start()

    def read_messages(self):
        for line in self.process.stdout:
            message = json.loads(line)
            self.evidence.record('app_server', message)
            self.messages.put(message)

    def send_request(self, method, parameters):
        self.next_request_id += 1
        message = {'id': self.next_request_id, 'method': method, 'params': parameters}
        self.evidence.record('client', message)
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()
        return self.next_request_id

    def wait_for(self, predicate, timeout=12):
        deadline = min(time.monotonic() + timeout, self.deadline)
        while True:
            for message in self.history:
                if predicate(message):
                    return message
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError('No matching app-server event')
            self.history.append(self.messages.get(timeout=remaining))

    def request(self, method, parameters):
        request_id = self.send_request(method, parameters)
        message = self.wait_for(lambda candidate: candidate.get('id') == request_id)
        if 'error' in message:
            raise RuntimeError(message)
        return message['result']

    def initialize(self):
        self.request('initialize', {
            'clientInfo': {'name': 'local_concurrency_probe', 'version': '1'},
            'capabilities': {'experimentalApi': True},
        })
        self.process.stdin.write('{"method":"initialized"}\n')
        self.process.stdin.flush()

    def wait_for_completion(self, thread_id, status=None):
        return self.wait_for(
            lambda message: message.get('method') == 'turn/completed'
            and message['params']['threadId'] == thread_id
            and (status is None or message['params']['turn']['status'] == status)
        )

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=3)
        self.reader.join(timeout=3)
        self.process.stdin.close()
        self.process.stdout.close()


def configure_isolated_home(home, base_url):
    (home / 'config.toml').write_text(f'''model = "local-synthetic-probe"
model_provider = "local_probe"
[model_providers.local_probe]
name = "Synthetic localhost probe"
base_url = "{base_url}"
wire_api = "responses"
requires_openai_auth = false
request_max_retries = 0
stream_max_retries = 0
stream_idle_timeout_ms = 30000
supports_websockets = false
''')


def verify_concurrent_turns(client, provider, checkout, evidence):
    client.initialize()
    thread_ids = {}
    for owner in ('alpha', 'beta'):
        result = client.request('thread/start', {
            'cwd': str(checkout),
            'ephemeral': True,
            'model': 'local-synthetic-probe',
            'modelProvider': 'local_probe',
        })
        thread_ids[owner] = result['thread']['id']

    start_requests = {}
    for owner, thread_id in thread_ids.items():
        start_requests[owner] = client.send_request('turn/start', {
            'threadId': thread_id,
            'input': [{'type': 'text',
                       'text': owner.upper() + '_LOCAL_PROBE Respond with a short sentence.'}],
            'approvalPolicy': 'never',
            'sandboxPolicy': {'type': 'readOnly'},
        })

    turn_ids = {}
    for owner, request_id in start_requests.items():
        response = client.wait_for(lambda message: message.get('id') == request_id)
        turn_ids[owner] = response['result']['turn']['id']
        client.wait_for(
            lambda message: message.get('method') == 'turn/started'
            and message['params']['threadId'] == thread_ids[owner]
        )
    accepted_owners = [provider.accepted_owners.get(timeout=15) for _ in range(2)]
    assert set(accepted_owners) == {'alpha', 'beta'}, accepted_owners
    assert not any(message.get('method') == 'turn/completed' for message in client.history)
    print('OBSERVED: both turn/started events and two held localhost model requests '
          'before release', flush=True)
    evidence.record('both_active_barrier', {
        'threads': thread_ids,
        'turns': turn_ids,
        'provider_requests': accepted_owners,
    })

    client.request('turn/interrupt', {
        'threadId': thread_ids['alpha'],
        'turnId': turn_ids['alpha'],
    })
    client.wait_for_completion(thread_ids['alpha'], 'interrupted')
    beta_thread = client.request('thread/read', {'threadId': thread_ids['beta']})
    beta_status = beta_thread['thread']['status']
    print('OBSERVED: alpha interrupted; beta status', beta_status, flush=True)
    assert beta_status['type'] == 'active', beta_status
    evidence.record('independent_interrupt_barrier', {
        'alpha': 'interrupted',
        'beta_status': beta_status,
    })

    provider.release_events['beta'].set()
    completion = client.wait_for_completion(thread_ids['beta'])
    status = completion['params']['turn']['status']
    print('OBSERVED: beta terminal status', status, flush=True)
    assert status == 'completed', completion


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--evidence-dir',
        type=pathlib.Path,
        help='New directory to retain compact evidence (default: temporary directory)',
    )
    arguments = parser.parse_args()
    executable = shutil.which('codex')
    if executable is None:
        parser.error('codex executable is unavailable on PATH')
    version = subprocess.run(
        [executable, '--version'],
        check=True,
        capture_output=True,
        text=True,
        timeout=5,
        env={'PATH': os.environ.get('PATH', '')},
    ).stdout.strip()
    if arguments.evidence_dir is None:
        directory = pathlib.Path(tempfile.mkdtemp(prefix='codex-concurrent-local-'))
    else:
        directory = arguments.evidence_dir.resolve()
        directory.mkdir(parents=True, exist_ok=False)
    print('Installed:', version, flush=True)
    print('Provider: synthetic localhost Responses; no remote model inference or UI checks',
          flush=True)

    evidence = EvidenceLog(directory)
    home = directory / 'home'
    checkout = directory / 'checkout'
    home.mkdir()
    checkout.mkdir()
    provider = LocalResponsesProvider(evidence)
    provider.start()
    client = None
    try:
        configure_isolated_home(home, provider.base_url)
        # An explicit environment allowlist excludes all inherited credentials and proxies.
        environment = {
            'PATH': os.environ.get('PATH', ''),
            'HOME': str(home),
            'CODEX_HOME': str(home),
            'TMPDIR': str(directory),
            'LANG': os.environ.get('LANG', 'en_US.UTF-8'),
        }
        with (directory / 'stderr.log').open('w') as stderr:
            client = AppServerClient(executable, environment, evidence, stderr)
            try:
                verify_concurrent_turns(client, provider, checkout, evidence)
            finally:
                client.close()
                client = None
        evidence.record('result', {
            'passed': True,
            'version': version,
            'synthetic_local_provider': True,
            'real_remote_model': False,
        })
        print('PASS evidence directory:', directory, flush=True)
    except Exception as error:
        evidence.record('result', {'passed': False, 'error': repr(error)})
        print('FAIL', repr(error), 'evidence directory:', directory, flush=True)
        raise
    finally:
        if client is not None:
            client.close()
        provider.close()
        shutil.rmtree(home, ignore_errors=True)
        shutil.rmtree(checkout, ignore_errors=True)


if __name__ == '__main__':
    main()
