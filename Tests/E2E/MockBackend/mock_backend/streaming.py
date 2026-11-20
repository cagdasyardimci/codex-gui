"""Independent turn workers, with serialized state updates and cancellation."""
import json
import os
from pathlib import Path
import threading
import time


class Stream:
    def __init__(self, engine, thread, turn, item):
        self.engine, self.thread, self.turn, self.item = engine, thread, turn, item
        self.cancelled = threading.Event()
        self.worker = threading.Thread(target=self.run, daemon=True)
        self.questions = []

    def emit(self, method, **values):
        self.engine.transport.event(method, {'threadId': self.thread['id'],
                                   'turnId': self.turn['id'], **values})

    def run(self):
        engine = self.engine
        try:
            text = self.turn['items'][0]['content'][0]['text']
            cold_history = engine.scenario.get('desktopHistory') and text == 'Queued request from another client'
            with engine.lock:
                self.emit('turn/started', turn=self.turn)
                for item in self.turn['items']:
                    if not cold_history or item is not self.item:
                        self.emit('item/started', item=item)
                if cold_history:
                    self.emit_history_commands()
                    self.emit('item/started', item=self.item)
            if engine.scenario.get('codingProbe'):
                self.read_probe_marker()
            desktop_turn = engine.scenario.get('desktopTurn')
            finish_during_quit = engine.scenario.get('desktopQuit') and text == 'Complete during Quit confirmation'
            hold = ((desktop_turn or engine.scenario.get('desktopQueue')) and text == 'Hold this fixture turn') or finish_during_quit
            quit_command = None
            if hold and engine.scenario.get('desktopQuit'):
                with engine.lock:
                    quit_command = {'id': 'fixture-pending-command', 'type': 'commandExecution',
                                    'command': 'Fixture command', 'status': 'inProgress',
                                    'cwd': self.thread['cwd']}
                    self.turn['items'].append(quit_command)
                    engine.state.save()
                    self.emit('item/started', item=quit_command)
            if desktop_turn and not hold:
                if self.approve_probe_read('fixture-turn-command'):
                    self.ask_question()
                else:
                    self.cancelled.set()
            elif engine.scenario.get('questions'):
                self.ask_question()
            if hold or engine.scenario['mode'] == 'stall':
                self.cancelled.wait(2 if finish_during_quit else None)
            else:
                for chunk in engine.scenario['chunks']:
                    with engine.lock:
                        if self.cancelled.is_set():
                            break
                        self.item['text'] += chunk
                        self.emit('item/agentMessage/delta', itemId=self.item['id'], delta=chunk)
                        engine.state.save()
                    if self.cancelled.wait(engine.scenario['intervalSeconds']):
                        break
            with engine.lock:
                self.turn['status'] = 'interrupted' if self.cancelled.is_set() else 'completed'
                self.turn['completedAt'] = int(time.time()) if engine.scenario.get('desktopHistory') else time.time()
                self.turn['durationMs'] = (self.turn['completedAt'] - self.turn['startedAt']) * 1000
                self.emit('item/completed', item=self.item)
                engine.active.pop(self.thread['id'], None)
                engine.state.save()
                self.emit('turn/completed', turn=self.turn)
                engine.transport.event('thread/status/changed', {
                    'threadId': self.thread['id'], 'status': {'type': 'idle'}})
            if quit_command and self.thread['id'].startswith('other-'):
                time.sleep(0.2)
                with engine.lock:
                    quit_command['status'] = 'completed'
                    engine.state.save()
                    self.emit('item/completed', item=quit_command)
        except (BrokenPipeError, OSError) as error:
            engine.report_failure(error)

    def emit_history_commands(self):
        for label, output in [('Inspect fixture directory', 'notes/\n'), ('Read current fixture', 'Café 日本語\n')]:
            command = {'id': self.engine.state.identity('command'), 'type': 'commandExecution',
                       'command': label, 'cwd': self.thread['cwd'], 'commandActions': [],
                       'status': 'inProgress', 'aggregatedOutput': None}
            self.turn['items'].insert(-1, command)
            self.emit('item/started', item=command)
            self.emit('item/commandExecution/outputDelta', itemId=command['id'], delta=output)
            command.update(status='completed', exitCode=0)
            self.emit('item/completed', item=command)
            command['aggregatedOutput'] = output

    def read_probe_marker(self):
        engine = self.engine
        with engine.lock:
            command_id = engine.state.identity('command')
        if os.name != 'nt' and not self.approve_probe_read(command_id):
            self.cancelled.set()
            return

        fixture = Path(self.thread['cwd']) / 'codex-gui-probe.txt'
        command = {'id': command_id, 'type': 'commandExecution',
                   'command': 'read fixture marker', 'cwd': self.thread['cwd'],
                   'aggregatedOutput': fixture.read_text(encoding='utf-8'),
                   'exitCode': 0, 'status': 'completed'}
        with engine.lock:
            self.turn['items'].append(command)
            self.emit('item/completed', item=command)

    def approve_probe_read(self, command_id):
        engine = self.engine
        request_id = 'qa-approval-' + command_id
        prompt = {'ready': threading.Event(), 'decision': None, 'threadId': self.thread['id']}
        params = {'threadId': self.thread['id'], 'turnId': self.turn['id'], 'itemId': command_id,
                  'command': "/bin/bash -lc '/bin/cat -- ./codex-gui-probe.txt'",
                  'cwd': self.thread['cwd'], 'kind': 'command',
                  'availableDecisions': ['accept', 'decline']}
        with engine.lock:
            engine.command_approvals[request_id] = prompt
            engine.transport.send({'method': 'item/commandExecution/requestApproval',
                                   'id': request_id, 'params': params})
        try:
            while not prompt['ready'].wait(0.2) and not self.cancelled.is_set():
                pass
            return prompt['decision'] == 'accept'
        finally:
            with engine.lock:
                engine.command_approvals.pop(request_id, None)

    def ask_question(self):
        text = self.turn['items'][0]['content'][0]['text'].lower()
        blocking = 'plan' in text
        free = 'free' in text
        mixed = 'mixed' in text
        options = [{'label': 'Composer', 'description': 'Review the composer'},
                   {'label': 'Transcript', 'description': 'Review the transcript'},
                   {'label': 'Settings', 'description': 'Review settings'}]
        question = {'id': 'area', 'header': 'Area',
                    'question': 'Which part of codex-gui would you like to review?',
                    'options': options, 'isOther': True, 'isSecret': False}
        free_question = {'id': 'details', 'header': 'Details',
                         'question': 'What would you like to improve?',
                         'options': None, 'isOther': True, 'isSecret': False}
        questions = [free_question, question] if mixed else [free_question if free else question]
        self.questions = questions
        ready = threading.Event()
        request_id = 'qa-question-' + self.turn['id']
        with self.engine.lock:
            self.engine.questions[request_id] = (self, ready)
            params = {'threadId': self.thread['id'], 'turnId': self.turn['id'],
                      'itemId': self.item['id'], 'isBlocking': blocking,
                      'autoResolutionMs': None, 'questions': questions}
            self.engine.transport.trace({'direction': 'server-request', 'id': request_id,
                                         'method': 'item/tool/requestUserInput', 'params': params})
            self.engine.transport.send({'id': request_id, 'method': 'item/tool/requestUserInput',
                                        'params': params})
        while not ready.wait(0.2) and not self.cancelled.is_set():
            pass
        with self.engine.lock:
            self.engine.questions.pop(request_id, None)

    def record_question_reply(self, answers):
        replies = [
            {'questionItemId': question['id'], 'question': question['question'],
             'answer': '\n'.join(answers.get(question['id'], {}).get('answers', []))}
            for question in self.questions
        ]
        body = ('<send_user_message_question_reply>\n' + json.dumps(replies, ensure_ascii=True)
                + '\n</send_user_message_question_reply>')
        item = {'id': self.engine.state.identity('reply'), 'type': 'userMessage',
                'content': [{'type': 'text', 'text': body}]}
        self.turn['items'].append(item)
        self.thread['preview'] = body
        self.engine.state.save()
        self.emit('item/completed', item=item)
        if self.engine.scenario.get('desktopWorkflow'):
            target = Path(self.thread['cwd']) / 'workflow-notes.txt'
            if target.read_text(encoding='utf-8') != 'Before fixture approval\n':
                raise ValueError('Expected the approved fixture checkout baseline')
            target.write_bytes('After fixture approval 日本語\n'.encode('utf-8'))
            changes = [{
                'path': str(target), 'kind': {'type': 'update', 'move_path': None},
                'diff': '@@ -1 +1 @@\n-Before fixture approval\n+After fixture approval 日本語',
            }]
            item = {
                'id': self.engine.state.identity('file-change'), 'type': 'fileChange',
                'status': 'completed', 'changes': changes,
            }
            self.turn['items'].append(item)
            self.engine.state.save()
            self.emit('item/fileChange/patchUpdated', itemId=item['id'], changes=changes)
            self.emit('item/completed', item=item)
