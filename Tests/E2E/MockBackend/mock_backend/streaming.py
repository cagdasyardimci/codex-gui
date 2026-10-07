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
