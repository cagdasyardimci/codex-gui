"""Focused app-server request handlers; unsupported operations fail explicitly."""
import copy
import sys
import threading
import time

from .streaming import Stream
from .transport import ProtocolError


class Server:
    def __init__(self, scenario, state, transport):
        self.scenario, self.state, self.transport = scenario, state, transport
        self.lock = threading.RLock()
        self.active = {}
        self.actions = []
        self.failure = None

    def report_failure(self, error):
        self.failure = error
        print('Mock backend worker failed: ' + str(error), file=sys.stderr, flush=True)

    def thread(self, identity):
        for thread in self.state.threads:
            if thread['id'] == identity:
                return thread
        raise ProtocolError(-32001, 'Unknown thread: ' + str(identity))

    def summary(self, thread):
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
        if method == 'account/read':
            return {'account': {'type': 'chatgpt', 'email': 'fixture@example.invalid'},
                    'requiresOpenaiAuth': False}
        if method == 'account/rateLimits/read':
            return {'rateLimits': {'primary': None, 'secondary': None}, 'rateLimitResetCredits': None}
        if method == 'model/list':
            return {'data': [{'id': 'qa-model', 'model': 'qa-model', 'displayName': 'QA fixture model',
                    'supportedReasoningEfforts': [{'reasoningEffort': 'medium'}],
                    'defaultReasoningEffort': 'medium', 'isDefault': True}], 'nextCursor': None}
        if method == 'skills/list':
            return {'data': [{'cwd': cwd, 'skills': [], 'errors': []} for cwd in p.get('cwds', [])]}
        if method == 'collaborationMode/list':
            return {'data': [{'name': 'Default', 'mode': 'default', 'model': None, 'reasoning_effort': None}]}
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
            self.state.threads.append(thread)
            return {'thread': self.summary(thread), **self.settings(thread)}
        if method in ('thread/read', 'thread/resume'):
            thread = self.thread(p.get('threadId'))
            return {'thread': {**self.summary(thread), 'turns': thread['turns']}, **self.settings(thread)}
        if method in ('thread/turns/list', 'thread/items/list'):
            thread = self.thread(p.get('threadId'))
            if method == 'thread/turns/list':
                turns = list(reversed(thread['turns']))
                if p.get('itemsView') == 'notLoaded':
                    turns = [{**t, 'items': [], 'itemsView': 'notLoaded'} for t in turns]
                return {'data': turns, 'nextCursor': None}
            turn = next((t for t in thread['turns'] if t['id'] == p.get('turnId')), None)
            if not turn:
                raise ProtocolError(-32001, 'Unknown turn')
            return {'data': turn['items'], 'nextCursor': None}
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
        if method == 'turn/interrupt':
            stream = self.active.get(p.get('threadId'))
            if not stream or stream.turn['id'] != p.get('turnId'):
                raise ProtocolError(-32002, 'Interrupt does not match an active turn')
            self.actions.append(stream.cancelled.set)
            return {}
        raise ProtocolError(-32601, 'Unsupported fixture method: ' + method)

    def start(self, p):
        thread = self.thread(p.get('threadId'))
        if thread['id'] in self.active:
            raise ProtocolError(-32002, 'Thread already has an active turn')
        if p.get('cwd') and p['cwd'] != thread.get('cwd'):
            raise ProtocolError(-32602, 'Turn cwd does not match thread')
        inputs = p.get('input')
        if not isinstance(inputs, list) or not inputs or any(not isinstance(i, dict) or i.get('type') != 'text' or not isinstance(i.get('text'), str) for i in inputs):
            raise ProtocolError(-32602, 'Fixture supports text inputs only')
        if self.scenario['mode'] == 'error':
            raise ProtocolError(self.scenario['error']['code'], self.scenario['error']['message'])
        turn_id = self.state.identity('turn')
        user = {'id': self.state.identity('user'), 'type': 'userMessage', 'content': inputs}
        assistant = {'id': self.state.identity('assistant'), 'type': 'agentMessage', 'text': ''}
        turn = {'id': turn_id, 'status': 'inProgress', 'startedAt': time.time(),
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
