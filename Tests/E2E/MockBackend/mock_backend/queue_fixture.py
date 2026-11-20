"""Exercise queued work through the installed desktop protocol fixture."""

import copy

from .transport import ProtocolError


def queue_request(server, method, params):
    thread_id = server.thread(params.get('threadId'))['id']
    if server.scenario['desktopQueue'] == 'legacy':
        raise ProtocolError(-32600, 'user message queue is unavailable')
    queues = server.state.data.setdefault('fixtureQueues', {})
    entries = queues.setdefault(thread_id, [])
    action = method.rsplit('/', 1)[-1]
    if action == 'list':
        return {'data': entries, 'nextCursor': None}

    def changed():
        server.transport.event('thread/queue/changed', {'threadId': thread_id})

    if action == 'add':
        if thread_id not in server.active:
            raise ProtocolError(-32600, 'Fixture add requires an active turn')
        entry = {
            'id': server.state.identity('queue-entry'),
            'clientUserMessageId': params['clientUserMessageId'],
            'input': params['input'],
        }
        if any(existing['clientUserMessageId'] == entry['clientUserMessageId'] for existing in entries):
            raise ProtocolError(-32600, 'Duplicate client receipt')
        entries.append(entry)
        server.actions.append(changed)
        return {'queuedSubmission': entry}
    if action == 'reorder':
        order = params['queuedSubmissionIds']
        by_id = {entry['id']: entry for entry in entries}
        if len(order) != len(entries) or set(order) != set(by_id):
            raise ProtocolError(-32600, 'Captured order no longer matches')
        entries[:] = [by_id[key] for key in order]
        server.actions.append(changed)
        return {}
    identity = params.get('queuedSubmissionId')
    entry = next((row for row in entries if row['id'] == identity), None)
    if action == 'delete':
        if entry:
            entries.remove(entry)
            server.actions.append(changed)
        return {'deleted': entry is not None}
    if entry is None:
        raise ProtocolError(-32600, f'queued submission not found: {identity}')
    if action == 'update':
        entry['input'] = params['input']
        server.actions.append(changed)
        return {'queuedSubmission': entry}
    if action == 'start':
        if thread_id in server.active:
            raise ProtocolError(-32600, 'thread already has an active or pending turn')
        turn = server.start({
            'threadId': thread_id, 'clientUserMessageId': entry['clientUserMessageId'],
            'input': entry['input'],
        })
        entries.remove(entry)
        server.actions.append(changed)
        return turn
    raise ProtocolError(-32601, 'Unsupported fixture queue method')


def steer_request(server, params):
    thread_id = params['threadId']
    stream = server.active.get(thread_id)
    if not stream or stream.turn['id'] != params['expectedTurnId']:
        raise ProtocolError(-32600, 'Steer does not match the captured active turn')
    item = {
        'type': 'userMessage', 'id': server.state.identity('user'),
        'clientId': params['clientUserMessageId'], 'content': copy.deepcopy(params['input']),
    }
    stream.turn['items'].append(item)
    server.actions.append(lambda: stream.emit('item/completed', item=item))
    return {'turnId': stream.turn['id']}
