"""Independent turn workers, with serialized state updates and cancellation."""
import threading
import time


class Stream:
    def __init__(self, engine, thread, turn, item):
        self.engine, self.thread, self.turn, self.item = engine, thread, turn, item
        self.cancelled = threading.Event()
        self.worker = threading.Thread(target=self.run, daemon=True)

    def emit(self, method, **values):
        self.engine.transport.event(method, {'threadId': self.thread['id'],
                                   'turnId': self.turn['id'], **values})

    def run(self):
        engine = self.engine
        try:
            with engine.lock:
                self.emit('turn/started', turn=self.turn)
                for item in self.turn['items']:
                    self.emit('item/started', item=item)
            if engine.scenario.get('questions'):
                self.ask_question()
            if engine.scenario['mode'] == 'stall':
                self.cancelled.wait()
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
                self.turn['completedAt'] = time.time()
                self.turn['durationMs'] = (self.turn['completedAt'] - self.turn['startedAt']) * 1000
                self.emit('item/completed', item=self.item)
                engine.active.pop(self.thread['id'], None)
                engine.state.save()
                self.emit('turn/completed', turn=self.turn)
                engine.transport.event('thread/status/changed', {
                    'threadId': self.thread['id'], 'status': {'type': 'idle'}})
        except (BrokenPipeError, OSError) as error:
            engine.report_failure(error)

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
