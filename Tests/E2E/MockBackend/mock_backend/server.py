"""Focused app-server request handlers; unsupported operations fail explicitly."""
import copy
import sys
import threading
import time
from pathlib import Path

from .streaming import Stream
from .queue_fixture import queue_request, steer_request
from .transport import ProtocolError


class Server:
    def __init__(self, scenario, state, transport):
        self.scenario, self.state, self.transport = scenario, state, transport
        self.lock = threading.RLock()
        self.active = {}
        self.actions = []
        self.failure = None
        self.questions = {}
        self.command_approvals = {}
        self.login_id = None
        self.canceled_login_id = None

    def resolve_request(self, response):
        with self.lock:
            command = self.command_approvals.pop(response['id'], None)
            if command:
                command['decision'] = response.get('result', {}).get('decision')
                self.transport.trace({'direction': 'command-approval-response', **response})
                if self.scenario.get('desktopTurn'):
                    self.transport.event('serverRequest/resolved', {
                        'threadId': command['threadId'], 'requestId': response['id']})
                command['ready'].set()
                return
            pending = self.questions.pop(response['id'], None)
            if pending:
                stream, ready = pending
                self.transport.trace({'direction': 'question-response', **response})
                if self.scenario.get('desktopTurn'):
                    stream.record_question_reply(response.get('result', {}).get('answers', {}))
                self.transport.event('serverRequest/resolved', {
                    'threadId': stream.thread['id'], 'requestId': response['id']})
                ready.set()

    def report_failure(self, error):
        self.failure = error
        print('Mock backend worker failed: ' + str(error), file=sys.stderr, flush=True)

    def thread(self, identity):
        for thread in self.state.threads:
            if thread['id'] == identity:
                return thread
        raise ProtocolError(-32001, 'Unknown thread: ' + str(identity))

    def summary(self, thread):
        if self.scenario.get('desktopHistory'):
            status = ({'type': 'active', 'activeFlags': []}
                      if thread['id'] in self.active else {'type': 'idle'})
            return {k: copy.deepcopy(v) for k, v in thread.items() if k != 'turns'} | {
                'cwd': thread['cwd'], 'createdAt': 1, 'updatedAt': int(time.time()),
                'status': status, 'turns': []}
        return {k: copy.deepcopy(v) for k, v in thread.items() if k != 'turns'} | {
            'cwd': thread.get('cwd', ''), 'updatedAt': time.time(),
            'status': {'type': 'active' if thread['id'] in self.active else 'idle'}, 'turns': []}

    def settings(self, thread):
        return {'model': 'qa-model', 'cwd': thread.get('cwd', ''), 'reasoningEffort': 'medium',
                'approvalPolicy': 'never', 'sandbox': 'workspace-write',
                'sandboxPolicy': {'type': 'workspaceWrite', 'writableRoots': [thread.get('cwd', '')]}}

    def handle(self, method, params):
        with self.lock:
            result = self.dispatch(method, params)
            self.state.save()
            return copy.deepcopy(result)

    def after_reply(self):
        actions, self.actions = self.actions, []
        for action in actions:
            action()

    def dispatch(self, method, p):
        if method == 'initialize':
            return {'userAgent': 'structured-qa-backend/1'}
        if method == 'windowsSandbox/readiness' and self.scenario.get('desktopHistory'):
            return {'status': self.state.data.get('windowsSandboxReadiness', 'ready')}
        if method == 'windowsSandbox/setupStart' and self.scenario.get('desktopWindowsSandbox'):
            return self.start_fixture_sandbox(p)
        if self.scenario.get('desktopAccount'):
            if method == 'account/read':
                email = self.state.data.get('fixtureAccountEmail')
                account = {'type': 'chatgpt', 'email': email, 'planType': 'plus'} if email else None
                return {'account': account, 'requiresOpenaiAuth': True}
            if method == 'account/login/start':
                return self.start_fixture_login(p)
            if method == 'account/login/cancel':
                identity = p.get('loginId')
                if identity != self.login_id or not self.login_id:
                    return {'status': 'notFound'}
                self.canceled_login_id = self.login_id
                self.login_id = None
                return {'status': 'canceled'}
            if method == 'model/list':
                if p.get('cursor') == 'visible-models':
                    return {'data': [self.desktop_model('fixture-default', False)], 'nextCursor': None}
                return {'data': [self.desktop_model('fixture-hidden', True)], 'nextCursor': 'visible-models'}
        if method == 'account/read':
            account = {'type': 'chatgpt', 'email': 'fixture@example.invalid'}
            if self.scenario.get('codingProbe') or self.scenario.get('desktopHistory'):
                account['planType'] = 'plus'
            return {'account': account, 'requiresOpenaiAuth': False}
        if method == 'account/rateLimits/read':
            return {'rateLimits': {'primary': None, 'secondary': None}, 'rateLimitResetCredits': None}
        if method == 'model/list':
            if self.scenario.get('desktopHistory'):
                return {'data': [self.desktop_model('fixture-default', False)], 'nextCursor': None}
            return {'data': [{'id': 'qa-model', 'model': 'qa-model', 'displayName': 'QA fixture model',
                    'supportedReasoningEfforts': [{'reasoningEffort': 'medium'}],
                    'defaultReasoningEffort': 'medium', 'isDefault': True}], 'nextCursor': None}
        if method == 'config/read' and 'config' in self.state.data:
            return {'config': copy.deepcopy(self.state.data['config']),
                    'layers': [{'name': {'type': 'user'}, 'version': 'component-fixture-v1'}]}
        if method == 'configRequirements/read' and 'config' in self.state.data:
            return {'requirements': {}}
        if method == 'experimentalFeature/list' and 'config' in self.state.data:
            return {'data': [{'name': name, 'enabled': enabled}
                             for name, enabled in self.state.data['config'].get('features', {}).items()],
                    'nextCursor': None}
        if method == 'skills/list':
            return {'data': [{'cwd': cwd, 'skills': [], 'errors': []} for cwd in p.get('cwds', [])]}
        if method == 'collaborationMode/list':
            return {'data': [{'name': 'Default', 'mode': 'default', 'model': None, 'reasoning_effort': None},
                             {'name': 'Plan', 'mode': 'plan', 'model': None, 'reasoning_effort': None}]}
        if method == 'thread/list':
            cwd = p.get('cwd')
            if isinstance(cwd, list):
                cwd = cwd[0] if cwd else None
            for thread in self.state.threads:
                if cwd and not thread.get('cwd'):
                    thread['cwd'] = cwd
            rows = [self.summary(t) for t in self.state.threads
                    if t['archived'] == p.get('archived', False) and (not cwd or t.get('cwd') == cwd)]
            query = p.get('searchTerm', '').casefold()
            return {'data': [t for t in rows if query in t.get('name', '').casefold()], 'nextCursor': None}
        if method == 'thread/start':
            if not p.get('cwd'):
                raise ProtocolError(-32602, 'thread/start requires cwd')
            thread = {'id': self.state.identity('thread'), 'name': 'New fixture conversation',
                      'cwd': p['cwd'], 'archived': False, 'turns': []}
            if self.scenario.get('desktopHistory'):
                thread['preview'] = ''
            self.state.threads.append(thread)
            return {'thread': self.summary(thread), **self.settings(thread)}
        if method in ('thread/read', 'thread/resume'):
            thread = self.thread(p.get('threadId'))
            turns = thread['turns']
            if self.scenario.get('desktopHistory'):
                if method == 'thread/resume':
                    self.resume_history_fixture(thread)
                if p.get('excludeTurns') or p.get('includeTurns') is False:
                    turns = []
            return {'thread': {**self.summary(thread), 'turns': turns}, **self.settings(thread)}
        if method == 'thread/queue/list' and self.scenario.get('desktopHistory'):
            if self.scenario.get('desktopQueue'):
                return queue_request(self, method, p)
            return {'data': [], 'nextCursor': None}
        if method.startswith('thread/queue/') and self.scenario.get('desktopQueue'):
            return queue_request(self, method, p)
        if method in ('thread/turns/list', 'thread/items/list'):
            thread = self.thread(p.get('threadId'))
            if method == 'thread/turns/list':
                turns = list(reversed(thread['turns']))
                if p.get('cursor'):
                    offset = next((i for i, turn in enumerate(turns) if turn['id'] == p['cursor']), None)
                    if offset is None:
                        raise ProtocolError(-32602, 'Unknown turn page cursor')
                    turns = turns[offset + 1:]
                limit = p.get('limit') or len(turns)
                next_cursor = turns[limit - 1]['id'] if len(turns) > limit else None
                turns = turns[:limit]
                if p.get('itemsView') == 'notLoaded':
                    turns = [{**t, 'items': [], 'itemsView': 'notLoaded'} for t in turns]
                return {'data': turns, 'nextCursor': next_cursor}
            turn = next((t for t in thread['turns'] if t['id'] == p.get('turnId')), None)
            if not turn:
                raise ProtocolError(-32001, 'Unknown turn')
            items = list(reversed(turn['items'])) if p.get('sortDirection') == 'desc' else turn['items']
            if p.get('cursor'):
                offset = next((i for i, item in enumerate(items) if item['id'] == p['cursor']), None)
                if offset is None:
                    raise ProtocolError(-32602, 'Unknown item page cursor')
                items = items[offset + 1:]
            limit = p.get('limit') or len(items)
            next_cursor = items[limit - 1]['id'] if len(items) > limit else None
            return {'data': [{'turnId': turn['id'], 'item': item} for item in items[:limit]], 'nextCursor': next_cursor}
        if method in ('thread/name/set', 'thread/archive', 'thread/unarchive', 'thread/delete', 'thread/unsubscribe'):
            thread = self.thread(p.get('threadId'))
            if method == 'thread/name/set':
                thread['name'] = p['name']
            elif method == 'thread/delete':
                if thread['id'] in self.active:
                    raise ProtocolError(-32002, 'Cannot delete active thread')
                self.state.threads.remove(thread)
            elif method != 'thread/unsubscribe':
                thread['archived'] = method == 'thread/archive'
            return {}
        if method == 'turn/start':
            return self.start(p)
        if method == 'turn/steer' and self.scenario.get('desktopQueue'):
            return steer_request(self, p)
        if method == 'turn/interrupt':
            stream = self.active.get(p.get('threadId'))
            if not stream or stream.turn['id'] != p.get('turnId'):
                raise ProtocolError(-32002, 'Interrupt does not match an active turn')
            self.actions.append(stream.cancelled.set)
            return {}
        raise ProtocolError(-32601, 'Unsupported fixture method: ' + method)

    @staticmethod
    def desktop_model(identity, hidden):
        return {'id': identity, 'model': identity, 'displayName': 'Fixture model',
                'description': 'Local protocol fixture', 'hidden': hidden, 'isDefault': not hidden}

    def start_fixture_login(self, params):
        if params != {'type': 'chatgpt'} or self.login_id:
            raise ProtocolError(-32602, 'Expected a fresh ChatGPT sign-in')
        self.login_id = self.state.identity('browser-login')
        identity = self.login_id
        obsolete = self.canceled_login_id
        if obsolete:
            def deliver():
                self.transport.event('account/login/completed', {'loginId': obsolete, 'success': True})
                timer = threading.Timer(0.6, self.finish_fixture_login, args=(identity,))
                timer.daemon = True
                timer.start()
            self.actions.append(deliver)
        return {'type': 'chatgpt', 'loginId': identity,
                'authUrl': 'https://auth.openai.com/oauth/authorize?state=local-fixture'}

    def finish_fixture_login(self, identity):
        with self.lock:
            if identity != self.login_id:
                return
            self.login_id = None
            self.state.data['fixtureAccountEmail'] = 'subscriber@example.invalid'
            self.state.save()
            self.transport.event('account/login/completed', {'loginId': identity, 'success': True})

    def start_fixture_sandbox(self, params):
        readiness = self.state.data.get('windowsSandboxReadiness')
        mode = {'notConfigured': 'unelevated', 'updateRequired': 'elevated'}.get(readiness)
        if not mode or params != {'mode': mode, 'cwd': self.thread('history-first')['cwd']}:
            raise ProtocolError(-32602, 'Sandbox setup must keep the selected checkout and mode')
        def deliver():
            wrong = 'elevated' if mode == 'unelevated' else 'unelevated'
            self.transport.event('windowsSandbox/setupCompleted', {'mode': wrong, 'success': True})
            timer = threading.Timer(0.6, self.finish_fixture_sandbox, args=(mode,))
            timer.daemon = True
            timer.start()
        self.actions.append(deliver)
        return {'started': True}

    def finish_fixture_sandbox(self, mode):
        with self.lock:
            self.state.data['windowsSandboxReadiness'] = 'ready'
            self.state.save()
            self.transport.event('windowsSandbox/setupCompleted', {'mode': mode, 'success': True})

    def resume_history_fixture(self, thread):
        if self.scenario.get('desktopAttachments') or thread['id'] != 'history-first':
            return
        if not self.state.data.get('writerLockObserved'):
            self.state.data['writerLockObserved'] = True
            self.state.save()
            raise ProtocolError(-32000, 'Thread already has an active writer')
        if not self.state.data.get('queuedFixtureDispatch'):
            self.state.data['queuedFixtureDispatch'] = True
            self.start({
                'threadId': thread['id'],
                'input': [{'type': 'text', 'text': 'Queued request from another client'}],
            })

    def start(self, p):
        thread = self.thread(p.get('threadId'))
        if thread['id'] in self.active:
            raise ProtocolError(-32002, 'Thread already has an active turn')
        if p.get('cwd') and p['cwd'] != thread.get('cwd'):
            raise ProtocolError(-32602, 'Turn cwd does not match thread')
        inputs = p.get('input')
        accepts_attachments = self.scenario.get('desktopAttachments', False)
        if not isinstance(inputs, list) or not inputs or any(
            not isinstance(item, dict) or not (
                item.get('type') == 'text' and isinstance(item.get('text'), str)
                or accepts_attachments and item.get('type') in ('localImage', 'mention')
                and isinstance(item.get('path'), str) and Path(item['path']).is_file()
            ) for item in inputs
        ):
            raise ProtocolError(-32602, 'Fixture supports text inputs only')
        if self.scenario['mode'] == 'error':
            raise ProtocolError(self.scenario['error']['code'], self.scenario['error']['message'])
        turn_id = self.state.identity('turn')
        user = {'id': self.state.identity('user'), 'type': 'userMessage', 'content': inputs}
        if self.scenario.get('desktopTurn') or self.scenario.get('desktopQueue'):
            user['clientId'] = p.get('clientUserMessageId')
            if inputs[0]['text'] == 'Recover this fixture receipt':
                thread['turns'].append({'id': turn_id, 'status': 'completed', 'items': [user]})
                return {'turn': {}}
        assistant = {'id': self.state.identity('assistant'), 'type': 'agentMessage', 'text': ''}
        started = int(time.time()) if self.scenario.get('desktopHistory') else time.time()
        turn = {'id': turn_id, 'status': 'inProgress', 'startedAt': started,
                'items': [user, assistant], 'error': None}
        thread['turns'].append(turn)
        stream = Stream(self, thread, turn, assistant)
        self.active[thread['id']] = stream
        self.actions.append(stream.worker.start)
        return {'turn': turn}

    def close(self):
        with self.lock:
            streams = list(self.active.values())
        for stream in streams:
            stream.cancelled.set()
        for stream in streams:
            stream.worker.join(timeout=2)
