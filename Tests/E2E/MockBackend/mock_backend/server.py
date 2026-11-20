"""Focused app-server request handlers; unsupported operations fail explicitly."""
import copy
import json
import os
import sys
import threading
import time
from pathlib import Path

from .streaming import Stream
from .queue_fixture import queue_request, steer_request
from .transport import ProtocolError, UnconfirmedMutation


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
            timestamp = (1 if thread['id'].endswith('first') else 2) if (
                self.scenario.get('desktopSidebar') or self.scenario.get('desktopArchive')) else int(time.time())
            return {k: copy.deepcopy(v) for k, v in thread.items() if k != 'turns'} | {
                'cwd': thread['cwd'], 'createdAt': 1, 'updatedAt': timestamp,
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
            if method != 'initialize' or not self.scenario.get('desktopAutomaticTitles'):
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
            if self.scenario.get('desktopComposerSettings'):
                baseline = self.desktop_model('baseline-model', False)
                alternative = self.desktop_model('alternative-model', False)
                baseline.update(displayName='Baseline model', isDefault=True, defaultReasoningEffort='low', supportedReasoningEfforts=[
                    {'reasoningEffort': 'low', 'description': 'Low'}], serviceTiers=[])
                alternative.update(displayName='Alternative model', isDefault=False, defaultReasoningEffort='medium', supportedReasoningEfforts=[
                    {'reasoningEffort': 'medium', 'description': 'Medium'}, {'reasoningEffort': 'high', 'description': 'High'}],
                    serviceTiers=[{'id': 'fixture-turbo', 'name': 'Ultrafast'}])
                if self.scenario.get('desktopSlash'):
                    alternative['serviceTiers'].append({'id': 'priority', 'name': 'Fast'})
                return {'data': [baseline, alternative], 'nextCursor': None}
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
        if method == 'feedback/upload' and self.scenario.get('desktopFeedback'):
            self.thread(p['threadId'])
            if p['threadId'] == 'history-first':
                time.sleep(0.6)
                return {'threadId': 'fixture-feedback-receipt'}
            if p['threadId'] == 'history-second':
                self.state.data['config']['feedback']['enabled'] = False
                self.state.save()
                raise UnconfirmedMutation
            raise ProtocolError(-32602, 'Unexpected feedback target')
        if method == 'experimentalFeature/list' and 'config' in self.state.data:
            return {'data': [{'name': name, 'enabled': enabled}
                             for name, enabled in self.state.data['config'].get('features', {}).items()],
                    'nextCursor': None}
        if method == 'skills/list':
            if self.scenario.get('desktopContext'):
                cwd = p['cwds'][0]
                return {'data': [{'cwd': cwd, 'errors': [], 'skills': [
                    {'name': 'Review fixture', 'path': str(Path(cwd) / 'skill' / 'SKILL.md'), 'enabled': True},
                    {'name': 'Disabled fixture', 'path': str(Path(cwd) / 'skill' / 'SKILL.md'), 'enabled': False},
                ]}]}
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
                    if self.scenario.get('desktopChatDeletion'):
                        managed = Path(cwd).parent.name == 'managed'
                        if managed != (thread['id'] == 'managed-chat'):
                            continue
                    thread['cwd'] = cwd
            rows = [self.summary(t) for t in self.state.threads
                    if t['archived'] == p.get('archived', False) and (not cwd or t.get('cwd') == cwd)]
            if self.scenario.get('desktopInspector'):
                rows = [row for row in rows if not row['id'].startswith('inspector-child-')]
            if self.scenario.get('desktopMessageSearch') and cwd and not p.get('archived'):
                if p.get('cursor') == 'search-chat-directory-next':
                    return {'data': rows[1:], 'nextCursor': None}
                return {'data': rows[:1], 'nextCursor': 'search-chat-directory-next' if len(rows) > 1 else None}
            if self.scenario.get('desktopArchive') and not cwd and p.get('archived'):
                if p.get('cursor') == 'archive-next':
                    return {'data': rows[35:], 'nextCursor': None}
                if p.get('cursor') == 'archive-after-replay':
                    return {'data': rows[34:], 'nextCursor': None}
                cursor = 'archive-next'
                if self.state.data.pop('replayArchivedThread', False):
                    prior = self.summary(self.thread('history-first'))
                    rows = [{**prior, 'archived': True}, *rows]
                    self.state.data['returnedObsoleteArchive'] = True
                    cursor = 'archive-after-replay'
                return {'data': rows[:35], 'nextCursor': cursor if len(rows) > 35 else None}
            query = p.get('searchTerm', '').casefold()
            return {'data': [t for t in rows if query in t.get('name', '').casefold()], 'nextCursor': None}
        if method == 'thread/start':
            if not p.get('cwd'):
                raise ProtocolError(-32602, 'thread/start requires cwd')
            if self.scenario.get('desktopAutomaticTitles') and p.get('ephemeral'):
                self.state.path = None
                thread = {'id': f'title-helper-{os.getpid()}', 'name': '', 'preview': '',
                          'cwd': p['cwd'], 'archived': False, 'turns': []}
                self.state.threads.append(thread)
                return {'thread': self.summary(thread), **self.settings(thread)}
            thread = {'id': self.state.identity('thread'), 'name': 'New fixture conversation',
                      'cwd': p['cwd'], 'archived': False, 'turns': []}
            if self.scenario.get('desktopAutomaticTitles'):
                thread['name'] = ''
            if self.scenario.get('desktopHistory'):
                thread['preview'] = ''
            self.state.threads.append(thread)
            return {'thread': self.summary(thread), **self.settings(thread)}
        if method in ('thread/read', 'thread/resume'):
            thread = self.thread(p.get('threadId'))
            if (self.scenario.get('desktopArchive') and method == 'thread/read'
                    and thread['id'] == 'history-second' and self.thread('history-first')['archived']
                    and not self.state.data.get('becameActiveDuringArchive')):
                self.state.data['becameActiveDuringArchive'] = True
                return {'thread': {**self.summary(thread), 'status': {'type': 'active', 'activeFlags': []}}}
            if (method == 'thread/resume' and self.scenario.get('desktopConversationFork')
                    and thread['id'] == 'history-second' and not self.state.data.get('branchWriterObserved')):
                self.state.data['branchWriterObserved'] = True
                self.state.save()
                raise ProtocolError(-32000, 'Thread already has an active writer')
            if (method == 'thread/resume' and self.scenario.get('desktopPromptRevision')
                    and thread['id'] == 'revision-fork-2' and not self.state.data.get('forkBlockedOnce')):
                self.state.data['forkBlockedOnce'] = True
                self.state.save()
                raise ProtocolError(-32000, 'Thread already has an active writer')
            turns = thread['turns']
            if self.scenario.get('desktopHistory'):
                if method == 'thread/resume':
                    self.resume_history_fixture(thread)
                    if self.scenario.get('desktopSlash'):
                        self.actions.append(lambda: self.slash_usage(thread, 'first-saved-turn', 2560))
                if p.get('excludeTurns') or p.get('includeTurns') is False:
                    turns = []
            return {'thread': {**self.summary(thread), 'turns': turns}, **self.settings(thread)}
        if method == 'thread/fork' and self.scenario.get('desktopConversationFork'):
            return self.conversation_fork(p)
        if method == 'thread/fork' and self.scenario.get('desktopPromptRevision'):
            source = self.thread(p['threadId'])
            boundary = next((index for index, turn in enumerate(source['turns'])
                             if turn['id'] == p.get('beforeTurnId')), None)
            if boundary is None or not p.get('excludeTurns'):
                raise ProtocolError(-32602, 'Fork requires the captured before-turn boundary')
            number = self.state.data.get('revisionForks', 0) + 1
            self.state.data['revisionForks'] = number
            if number == 3:
                time.sleep(0.9)
            fork = {**source, 'id': f'revision-fork-{number}', 'name': f'Revision Fork {number}',
                    'turns': copy.deepcopy(source['turns'][:boundary])}
            self.state.threads.append(fork)
            return {'thread': self.summary(fork), **self.settings(fork)}
        if method == 'thread/queue/list' and self.scenario.get('desktopHistory'):
            if self.scenario.get('desktopQueue'):
                return queue_request(self, method, p)
            return {'data': [], 'nextCursor': None}
        if method.startswith('thread/queue/') and self.scenario.get('desktopQueue'):
            return queue_request(self, method, p)
        if method in ('thread/turns/list', 'thread/items/list'):
            thread = self.thread(p.get('threadId'))
            if method == 'thread/turns/list':
                if self.scenario.get('desktopInspector') and not p.get('cursor'):
                    if thread['id'] == 'inspector-child-slow':
                        time.sleep(0.45)
                    if thread['id'] == 'inspector-child-review' and not self.state.data.get('childUpdatePublished'):
                        self.actions.append(lambda: self.update_inspector_child(thread))
                if self.scenario.get('desktopMessageSearch') and thread['id'] == 'history-second':
                    time.sleep(0.35)
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
            if self.scenario.get('desktopArchive'):
                if method == 'thread/archive' and thread['id'] == 'history-second':
                    self.state.data['archiveRejected'] = True
                    self.state.save()
                    raise ProtocolError(-32000, 'Archive rejected by the fixture')
                if method == 'thread/unarchive' and thread['id'] == 'history-first' and not self.state.data.get('returnedObsoleteArchive'):
                    self.state.data['replayArchivedThread'] = True
            if method == 'thread/name/set':
                thread['name'] = p['name']
            elif method == 'thread/delete':
                if thread['id'] in self.active:
                    raise ProtocolError(-32002, 'Cannot delete active thread')
                if self.scenario.get('desktopChatDeletion') and thread['id'] == 'uncertain-delete':
                    self.state.data['retiredDuringDelete'] = True
                    self.state.save()
                    raise UnconfirmedMutation
                self.state.threads.remove(thread)
            elif method != 'thread/unsubscribe':
                thread['archived'] = method == 'thread/archive'
            if self.scenario.get('desktopArchive') and method == 'thread/unarchive':
                return {'thread': self.summary(thread)}
            return {}
        if method == 'turn/start':
            if self.scenario.get('desktopAutomaticTitles') and p.get('threadId', '').startswith('title-helper-'):
                prompt = p['input'][0]['text']
                structured = json.dumps({'title': '  Réparer   le flux  '}, ensure_ascii=False)
                if prompt.startswith('Reject malformed'):
                    structured = 'An invalid title response.'
                self.scenario = {
                    **self.scenario,
                    'mode': 'stall' if prompt.startswith('Keep the manual') else 'stream',
                    'chunks': [structured],
                    'intervalSeconds': 1.5,
                }
            if self.scenario.get('desktopComposerSettings'):
                time.sleep(0.55)
            return self.start(p)
        if method == 'thread/settings/update' and self.scenario.get('desktopSlash'):
            return self.slash_settings(p)
        if method == 'thread/compact/start' and self.scenario.get('desktopSlash'):
            return self.slash_compaction(p)
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

    def update_inspector_child(self, thread):
        self.state.data['childUpdatePublished'] = True
        turn = thread['turns'][-1]
        item = turn['items'][0]
        item['text'] = 'The child reported an updated result.'
        self.state.save()
        for delta in ('child ', 'reported ', 'another ', 'result'):
            self.transport.event('item/agentMessage/delta', {
                'threadId': thread['id'], 'turnId': turn['id'], 'itemId': item['id'], 'delta': delta,
            })

    def slash_usage(self, thread, turn, tokens):
        self.transport.event('thread/tokenUsage/updated', {
            'threadId': thread['id'], 'turnId': turn,
            'tokenUsage': {'last': {'inputTokens': 1024, 'totalTokens': tokens},
                           'total': {'totalTokens': 133_700}, 'modelContextWindow': 10_240},
        })

    def conversation_fork(self, params):
        source = self.thread(params['threadId'])
        capture = params.get('lastTurnId')
        if capture:
            count = next((index + 1 for index, turn in enumerate(source['turns']) if turn['id'] == capture), None)
        else:
            count = len(source['turns']) if params.get('deferGoalContinuation') else None
        if count is None or not params.get('excludeTurns'):
            raise ProtocolError(-32602, 'Invalid captured branch target')
        number = self.state.data.get('conversationForks', 0) + 1
        self.state.data['conversationForks'] = number
        fork = {**source, 'id': f'conversation-fork-{number}', 'name': f'Conversation Fork {number}',
                'turns': copy.deepcopy(source['turns'][:count])}
        self.state.threads.append(fork)
        if number == 1:
            source['turns'].extend({
                'id': f'more-recent-{index}', 'status': 'completed',
                'items': [{'id': f'new-answer-{index}', 'type': 'agentMessage', 'text': f'More recent response {index}.'}],
            } for index in range(105))
        if number == 3:
            self.state.save()
            raise UnconfirmedMutation()
        return {'thread': self.summary(fork), **self.settings(fork)}

    def slash_settings(self, params):
        thread = self.thread(params['threadId'])
        mode = params['collaborationMode']
        if mode.get('mode') not in ('plan', 'default') or not mode.get('settings', {}).get('model'):
            raise ProtocolError(-32602, 'Invalid captured plan settings')
        counter = self.state.data.get('slashSettingsCount', 0) + 1
        self.state.data['slashSettingsCount'] = counter
        self.state.data['slashMode'] = mode
        if counter == 3:
            self.state.save()
            raise UnconfirmedMutation()
        self.transport.event('thread/settings/updated', {
            'threadId': thread['id'], 'threadSettings': {'cwd': thread['cwd'], 'collaborationMode': mode},
        })
        return {}

    def slash_compaction(self, params):
        thread = self.thread(params['threadId'])
        if thread['id'] in self.active:
            raise ProtocolError(-32002, 'Cannot compact an active conversation')
        turn_id = self.state.identity('compact')
        turn = {'id': turn_id, 'status': 'inProgress', 'items': [], 'startedAt': int(time.time())}
        thread['turns'].append(turn)
        self.transport.event('turn/started', {'threadId': thread['id'], 'turn': turn})
        def finish():
            with self.lock:
                turn['status'] = 'completed'
                turn['completedAt'] = int(time.time())
                self.state.save()
                self.slash_usage(thread, turn_id, 1024)
                self.transport.event('thread/compacted', {'threadId': thread['id'], 'turnId': turn_id})
                self.transport.event('turn/completed', {'threadId': thread['id'], 'turn': turn})
        def schedule():
            timer = threading.Timer(0.65, finish)
            timer.daemon = True
            timer.start()
        self.actions.append(schedule)
        return {}

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
        context_inputs = ('localImage', 'mention', 'skill') if self.scenario.get('desktopContext') else ('localImage', 'mention')
        if not isinstance(inputs, list) or not inputs or any(
            not isinstance(item, dict) or not (
                item.get('type') == 'text' and isinstance(item.get('text'), str)
                or accepts_attachments and item.get('type') in context_inputs
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
