"""One backend process owns its run state; reconnects can restore saved histories."""
import copy
import json
import os
from pathlib import Path


class State:
    def __init__(self, scenario, path=None):
        self.path = Path(path) if path else None
        self.data = json.loads(self.path.read_text()) if self.path and self.path.exists() else {}
        self.threads = copy.deepcopy(self.data.get('threads', scenario['threads']))
        for thread in self.threads:
            thread.setdefault('turns', [])
            thread.setdefault('archived', False)
            # No worker survives a backend restart; mark abandoned turns honestly.
            for turn in thread['turns']:
                if turn['status'] == 'inProgress':
                    turn['status'] = 'interrupted'
        self.sequence = self.data.get('sequence', 0)

    def identity(self, prefix):
        self.sequence += 1
        return prefix + '-' + str(self.sequence)

    def save(self):
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.data.update(threads=self.threads, sequence=self.sequence)
            temporary = self.path.with_suffix('.tmp')
            temporary.write_text(json.dumps(self.data, ensure_ascii=True))
            os.replace(temporary, self.path)
