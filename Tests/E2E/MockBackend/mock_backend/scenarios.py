"""Load declarative scenarios from the mock backend package resources."""
import copy
import json
import math
from importlib import resources


def load(name, ancestors=()):
    if not isinstance(name, str) or not name or any(c not in 'abcdefghijklmnopqrstuvwxyz-' for c in name):
        raise ValueError('Invalid scenario name')
    if name in ancestors:
        raise ValueError('Scenario inheritance cycle')
    resource = resources.files('mock_backend').joinpath('scenarios').joinpath(name + '.json')
    value = json.loads(resource.read_text())
    parent = value.pop('extends', None)
    result = load(parent, ancestors + (name,)) if parent else {}
    result.update(value)
    threads = result.get('threads', [])
    if not threads or len({t['id'] for t in threads}) != len(threads):
        raise ValueError('Scenario needs unique thread IDs')
    interval = result.get('intervalSeconds', 2)
    if not isinstance(interval, (int, float)) or not math.isfinite(interval) or not 0 <= interval <= 60:
        raise ValueError('Invalid stream interval')
    if not isinstance(result.get('chunks'), list) or not all(isinstance(s, str) for s in result['chunks']):
        raise ValueError('Scenario chunks must be strings')
    if result.get('mode') not in ('stream', 'stall', 'error'):
        raise ValueError('Unknown scenario mode')
    return copy.deepcopy(result)
