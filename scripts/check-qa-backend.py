#!/usr/bin/env python3
"""Protocol smoke checks for the synthetic QA backend; uses only temporary files."""
import json
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time


BACKEND = Path(__file__).with_name('qa-backend.py')


class Backend:
    def __init__(self, directory, variant=None, initial_state=None, state_path=None):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.trace = self.directory / 'requests.jsonl'
        self.state = Path(state_path) if state_path else self.directory / 'state.json'
        state = dict(initial_state or {})
        if variant:
            state['qaVariant'] = variant
        if state:
            self.state.write_text(json.dumps(state))
        env = os.environ.copy()
        env['CODEX_GUI_QA_STATE'] = str(self.state)
        env['CODEX_GUI_QA_TRACE'] = str(self.trace)
        self.process = subprocess.Popen(
            [sys.executable, str(BACKEND)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, bufsize=1, env=env,
        )
        self.next_id = 1
        self.messages = []
        self.output = queue.Queue()
        self.reader = threading.Thread(target=self._read_output, daemon=True)
        self.reader.start()

    def _read_output(self):
        for line in self.process.stdout:
            self.output.put(json.loads(line))

    def _next_message(self, timeout=5):
        try:
            return self.output.get(timeout=timeout)
        except queue.Empty as error:
            if self.process.poll() is not None:
                raise AssertionError(
                    f'Synthetic backend exited: {self.process.stderr.read()}') from error
            raise AssertionError('Synthetic backend did not reply in time.') from error

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + '\n')
        self.process.stdin.flush()

    def request(self, method, params):
        request_id = self.next_id
        self.next_id += 1
        self.send({'id': request_id, 'method': method, 'params': params})
        while True:
            message = self._next_message()
            if message.get('id') == request_id:
                if 'error' in message:
                    raise AssertionError(f'{method} returned {message["error"]}')
                return message.get('result', {})
            self.messages.append(message)

    def wait_for(self, predicate, count=1, timeout=5):
        deadline = time.monotonic() + timeout
        while True:
            matches = [message for message in self.messages if predicate(message)]
            if len(matches) >= count:
                return matches
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise AssertionError(f'Expected {count} matching backend messages; got {len(matches)}.')
            self.messages.append(self._next_message(remaining))

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
        self.process.wait(timeout=3)


def check_available(directory):
    backend = Backend(directory)
    try:
        skills = backend.request('skills/list', {'cwds': [str(Path(directory) / 'project')]})
        skill_rows = skills['data'][0]['skills']
        assert any(row['name'] == 'qa-review' and row['enabled'] for row in skill_rows)
        assert any(row['name'] == 'qa-disabled' and not row['enabled'] for row in skill_rows)
        assert skills['data'][0]['errors'], 'partial discovery warning should remain visible'

        limits = backend.request('account/rateLimits/read', {})
        assert limits['rateLimits']['primary']['usedPercent'] == 34
        assert limits['rateLimits']['primary']['resetsAt'] == 1893456000
        assert limits['rateLimits']['secondary'] is None
        assert limits['rateLimitResetCredits']['availableCount'] == 1
        review = backend.request('thread/turns/list', {'threadId': 'qa-review'})
        turns = review['data']
        assert len(turns) == 2 and turns[0]['id'] == 'qa-review-turn-2'
        first_turn = next(turn for turn in turns if turn['id'] == 'qa-review-turn-1')
        changes = first_turn['items'][2]['changes']
        assert {'path': 'Sources/OldParser.swift', 'move': 'Sources/Parser.swift'} == {
            'path': changes[0]['path'], 'move': changes[0]['kind']['move_path']}
        assert 'Binary files' in changes[2]['diff']
        assert len(changes[3]['diff'].splitlines()[-1]) > 150
        validation = [item for item in first_turn['items'] if item['type'] == 'commandExecution']
        assert [item.get('exitCode') for item in validation] == [0, 1, None]

        context = backend.request('thread/turns/list', {'threadId': 'qa-context'})
        assert context['nextCursor'] == 'qa-context-older'
        assert any(item['id'] == 'qa-context-current-answer'
                   for turn in context['data'] for item in turn['items'])
        older = backend.request('thread/turns/list', {
            'threadId': 'qa-context', 'cursor': context['nextCursor']})
        assert older['nextCursor'] is None
        assert any(item['id'] == 'qa-context-decision'
                   for turn in older['data'] for item in turn['items'])

        started = backend.request('turn/start', {
            'threadId': 'qa-review',
            'input': [
                {'type': 'text', 'text': (
                    '$qa-review [specification] API compatibility: preserve existing callers. '
                    'Prompt: keep source compatibility. Question about this change: '
                    'Origin thread: qa-review\nOrigin turn: qa-review-turn-1\n'
                    'File: Sources/Parser.swift\nSection: hunk-1 @@ -1,2 +1,3 @@'
                ),
                 'text_elements': []},
                {'type': 'skill', 'name': 'qa-review',
                 'path': '/tmp/codex-gui-qa/skills/qa-review/SKILL.md'},
            ], 'model': 'gpt-5.6-luna', 'effort': 'low',
        })
        for _ in range(20):
            detail = backend.request('thread/read', {'threadId': 'qa-review'})
            if detail['thread']['status']['type'] == 'active':
                break
            time.sleep(0.025)
        else:
            raise AssertionError('Synthetic turn did not become active.')
        backend.request('turn/steer', {
            'threadId': 'qa-review', 'expectedTurnId': started['turn']['id'],
            'input': [{'type': 'text', 'text': 'Preserve the source-compatible API.', 'text_elements': []}],
        })
        backend.request('turn/interrupt', {
            'threadId': 'qa-review', 'turnId': started['turn']['id'],
        })
        records = [json.loads(line) for line in backend.trace.read_text().splitlines()]
        starts = [record for record in records if record['method'] == 'turn/start']
        assert starts and starts[-1]['threadId'] == 'qa-review'
        assert starts[-1]['input'][1]['type'] == 'skill'
        assert '$qa-review' in starts[-1]['input'][0]['text']
        assert 'Origin thread: qa-review' in starts[-1]['input'][0]['text']
        assert 'Origin turn: qa-review-turn-1' in starts[-1]['input'][0]['text']
        assert 'File: Sources/Parser.swift' in starts[-1]['input'][0]['text']
        assert 'Section: hunk-1' in starts[-1]['input'][0]['text']
        assert starts[-1]['model'] == 'gpt-5.6-luna' and starts[-1]['effort'] == 'low'
        steers = [record for record in records if record['method'] == 'turn/steer']
        assert steers and steers[-1]['threadId'] == 'qa-review'
        assert steers[-1]['expectedTurnId'] == started['turn']['id']
    finally:
        backend.close()


def check_unavailable(directory):
    backend = Backend(directory, variant='unavailable')
    try:
        skills = backend.request('skills/list', {'cwds': [str(Path(directory) / 'project')]})
        assert not skills['data'][0]['skills'] and skills['data'][0]['errors']
        request_id = backend.next_id
        backend.next_id += 1
        backend.send({
            'id': request_id, 'method': 'account/rateLimits/read', 'params': {},
        })
        while True:
            message = backend._next_message()
            if message.get('id') == request_id:
                assert message['error']['message'] == 'Synthetic usage unavailable.'
                break
    finally:
        backend.close()


def check_checkout_cwds(directory):
    alpha = Path(directory) / 'worktree-alpha'
    beta = Path(directory) / 'worktree-beta'
    alpha.mkdir(parents=True)
    beta.mkdir(parents=True)
    backend = Backend(Path(directory) / 'backend')
    try:
        fixtures = backend.request('thread/list', {'cwd': str(alpha), 'archived': False})['data']
        assert any(row['id'] == 'qa-review' for row in fixtures)
        assert all(row['cwd'] == str(alpha) for row in fixtures)
        assert backend.request('thread/list', {'cwd': str(beta), 'archived': False})['data'] == []

        first = backend.request('thread/start', {'cwd': str(alpha)})
        second = backend.request('thread/start', {'cwd': str(beta)})
        first_id = first['thread']['id']
        second_id = second['thread']['id']
        assert first_id != second_id
        assert first['cwd'] == first['thread']['cwd'] == str(alpha)
        assert second['cwd'] == second['thread']['cwd'] == str(beta)
        assert backend.request('thread/resume', {'threadId': first_id})['cwd'] == str(alpha)
        assert backend.request('thread/resume', {'threadId': second_id})['thread']['cwd'] == str(beta)
        alpha_ids = {row['id'] for row in backend.request('thread/list', {'cwd': str(alpha)})['data']}
        beta_ids = {row['id'] for row in backend.request('thread/list', {'cwd': str(beta)})['data']}
        assert first_id in alpha_ids and second_id not in alpha_ids
        assert second_id in beta_ids and first_id not in beta_ids
        combined = backend.request('thread/list', {'cwd': [str(alpha), str(beta)]})['data']
        assert {first_id, second_id}.issubset({row['id'] for row in combined})
        assert backend.request('thread/list', {'cwd': str(directory)})['data'] == []

        moved = backend.request('thread/resume', {'threadId': first_id, 'cwd': str(beta)})
        assert moved['cwd'] == moved['thread']['cwd'] == str(beta)
        assert first_id not in {row['id'] for row in backend.request('thread/list', {'cwd': str(alpha)})['data']}

        started = backend.request('turn/start', {
            'threadId': second_id, 'cwd': str(alpha),
            'input': [{'type': 'text', 'text': 'Synthetic cwd override', 'text_elements': []}],
        })
        assert backend.request('thread/read', {'threadId': second_id})['thread']['cwd'] == str(alpha)
        assert second_id in {row['id'] for row in backend.request('thread/list', {'cwd': str(alpha)})['data']}
        backend.wait_for(lambda message: message.get('method') == 'turn/started'
                         and message['params']['threadId'] == second_id)
        backend.request('turn/interrupt', {'threadId': second_id, 'turnId': started['turn']['id']})
        starts = [json.loads(line) for line in backend.trace.read_text().splitlines()]
        assert starts[-1]['cwd'] == str(alpha)
    finally:
        backend.close()


def check_interleaved_approvals(directory):
    alpha = Path(directory) / 'worktree-alpha'
    beta = Path(directory) / 'worktree-beta'
    alpha.mkdir(parents=True)
    beta.mkdir(parents=True)
    threads = [
        {'id': 'qa-task-control-alpha', 'name': 'Alpha task', 'preview': '',
         'archived': False, 'cwd': str(alpha)},
        {'id': 'qa-task-control-beta', 'name': 'Beta task', 'preview': '',
         'archived': False, 'cwd': str(beta)},
    ]
    backend = Backend(Path(directory) / 'backend', initial_state={'threads': threads})
    try:
        starts = {}
        for thread in threads:
            starts[thread['id']] = backend.request('turn/start', {
                'threadId': thread['id'],
                'input': [{'type': 'text', 'text': 'Synthetic overlapping task',
                           'text_elements': []}],
            })['turn']['id']

        approvals = backend.wait_for(
            lambda message: message.get('method') == 'item/commandExecution/requestApproval',
            count=2)
        by_thread = {message['params']['threadId']: message for message in approvals}
        assert set(by_thread) == set(starts)
        for thread in threads:
            approval = by_thread[thread['id']]
            assert approval['params']['turnId'] == starts[thread['id']]
            assert approval['params']['cwd'] == thread['cwd']
            assert approval['params']['approvalId'] == f'qa-callback-{starts[thread["id"]]}'
            assert backend.request('thread/read', {'threadId': thread['id']})['thread']['status']['type'] == 'active'
        assert by_thread['qa-task-control-alpha']['id'] != by_thread['qa-task-control-beta']['id']

        for thread_id in ('qa-task-control-beta', 'qa-task-control-alpha'):
            backend.send({'id': by_thread[thread_id]['id'], 'result': {'decision': 'decline'}})
        resolved = backend.wait_for(
            lambda message: message.get('method') == 'serverRequest/resolved', count=2)
        assert {(message['params']['threadId'], message['params']['requestId'])
                for message in resolved} == {
                    (thread_id, approval['id']) for thread_id, approval in by_thread.items()
                }
        for thread_id, turn_id in starts.items():
            backend.request('turn/interrupt', {'threadId': thread_id, 'turnId': turn_id})
        trace = [json.loads(line) for line in backend.trace.read_text().splitlines()]
        effective = {entry['threadId']: entry['cwd'] for entry in trace
                     if entry['method'] == 'turn/start'}
        assert effective == {thread['id']: thread['cwd'] for thread in threads}
    finally:
        backend.close()


def check_independent_client_persistence(directory):
    directory = Path(directory)
    directory.mkdir(parents=True)
    shared_state = directory / 'shared-state.json'
    alpha = directory / 'worktree-alpha'
    beta = directory / 'worktree-beta'
    alpha.mkdir()
    beta.mkdir()
    first = Backend(directory / 'first-client', state_path=shared_state)
    second = Backend(directory / 'second-client', state_path=shared_state)
    resumed = None
    try:
        first.request('initialize', {})
        second.request('initialize', {})
        first.request('thread/list', {'cwd': str(alpha)})
        second.request('thread/list', {'cwd': str(beta)})
        with ThreadPoolExecutor(max_workers=2) as executor:
            first_start = executor.submit(first.request, 'thread/start', {'cwd': str(alpha)})
            second_start = executor.submit(second.request, 'thread/start', {'cwd': str(beta)})
            first_id = first_start.result()['thread']['id']
            second_id = second_start.result()['thread']['id']
            assert first_id != second_id
            first_name = executor.submit(first.request, 'thread/name/set', {
                'threadId': first_id, 'name': 'Alpha independently saved'})
            second_archive = executor.submit(second.request, 'thread/archive', {
                'threadId': second_id})
            first_name.result()
            second_archive.result()

        first.close()
        resumed = Backend(directory / 'resumed-client', state_path=shared_state)
        first_restored = resumed.request('thread/resume', {'threadId': first_id})
        second_restored = second.request('thread/read', {'threadId': second_id})
        assert first_restored['cwd'] == str(alpha)
        assert first_restored['thread']['name'] == 'Alpha independently saved'
        assert second_restored['thread']['cwd'] == str(beta)
        assert second_restored['thread']['archived'] is True
        saved_threads = {thread['id']: thread for thread in json.loads(shared_state.read_text())['threads']}
        assert saved_threads[first_id]['name'] == 'Alpha independently saved'
        assert saved_threads[second_id]['archived'] is True
        assert saved_threads['qa-review']['cwd'] == str(alpha)

        second.request('thread/unarchive', {'threadId': second_id})
        first_turn = resumed.request('turn/start', {
            'threadId': first_id, 'cwd': str(alpha),
            'input': [{'type': 'text', 'text': 'First independent managed task'}],
        })['turn']['id']
        second_turn = second.request('turn/start', {
            'threadId': second_id, 'cwd': str(beta),
            'input': [{'type': 'text', 'text': 'Second independent managed task'}],
        })['turn']['id']
        for backend, thread_id, turn_id, cwd in (
                (resumed, first_id, first_turn, alpha),
                (second, second_id, second_turn, beta)):
            approval = backend.wait_for(
                lambda message: message.get('method') == 'item/commandExecution/requestApproval'
            )[0]
            assert approval['params']['threadId'] == thread_id
            assert approval['params']['turnId'] == turn_id
            assert approval['params']['cwd'] == str(cwd)
            backend.wait_for(lambda message: message.get('method') == 'turn/plan/updated'
                             and message['params']['threadId'] == thread_id)
            backend.wait_for(lambda message: message.get('method') == 'turn/diff/updated'
                             and message['params']['threadId'] == thread_id)

        resumed.request('turn/interrupt', {'threadId': first_id, 'turnId': first_turn})
        stopped = resumed.wait_for(lambda message: message.get('method') == 'turn/completed')[0]
        assert stopped['params']['threadId'] == first_id
        assert stopped['params']['turn']['status'] == 'interrupted'
        still_waiting = second.request('thread/read', {'threadId': second_id})['thread']['status']
        assert still_waiting == {'type': 'active', 'activeFlags': ['waitingOnApproval']}
        second_approval = second.wait_for(
            lambda message: message.get('method') == 'item/commandExecution/requestApproval'
        )[0]
        second.send({'id': second_approval['id'], 'result': {'decision': 'decline'}})
        resolved = second.wait_for(lambda message: message.get('method') == 'serverRequest/resolved')[0]
        assert resolved['params']['threadId'] == second_id
        assert resolved['params']['requestId'] == second_approval['id']
        second.request('turn/interrupt', {'threadId': second_id, 'turnId': second_turn})
    finally:
        first.close()
        second.close()
        if resumed:
            resumed.close()


def check_late_command_after_stop(directory):
    directory = Path(directory)
    alpha = directory / 'worktree-alpha'
    beta = directory / 'worktree-beta'
    alpha.mkdir(parents=True)
    beta.mkdir()
    backend = Backend(directory / 'backend', initial_state={'qaLateCommandDelaySeconds': 0.3})
    try:
        first_id = backend.request('thread/start', {'cwd': str(alpha)})['thread']['id']
        second_id = backend.request('thread/start', {'cwd': str(beta)})['thread']['id']
        first_turn = backend.request('turn/start', {
            'threadId': first_id, 'cwd': str(alpha),
            'input': [{'type': 'text', 'text': '[qa-late-command-after-stop]'}],
        })['turn']['id']
        second_turn = backend.request('turn/start', {
            'threadId': second_id, 'cwd': str(beta),
            'input': [{'type': 'text', 'text': 'Default task remains independent'}],
        })['turn']['id']
        approvals = backend.wait_for(
            lambda message: message.get('method') == 'item/commandExecution/requestApproval', count=2)
        first_approval = next(message for message in approvals
                              if message['params']['threadId'] == first_id)
        command_id = first_approval['params']['itemId']
        assert first_approval['params']['cwd'] == str(alpha)
        backend.send({'id': first_approval['id'], 'result': {'decision': 'accept'}})
        backend.wait_for(lambda message: message.get('method') == 'serverRequest/resolved'
                         and message['params']['threadId'] == first_id)
        backend.request('turn/interrupt', {'threadId': first_id, 'turnId': first_turn})
        stopped = backend.wait_for(lambda message: message.get('method') == 'turn/completed'
                                   and message['params']['threadId'] == first_id)[0]
        assert stopped['params']['turn']['id'] == first_turn
        assert stopped['params']['turn']['status'] == 'interrupted'
        pending_command = next(item for item in stopped['params']['turn']['items']
                               if item['id'] == command_id)
        assert pending_command['status'] == 'inProgress'
        assert pending_command['cwd'] == str(alpha)
        assert not any(message.get('method') == 'item/completed'
                       and message['params'].get('item', {}).get('id') == command_id
                       for message in backend.messages)

        output = backend.wait_for(
            lambda message: message.get('method') == 'item/commandExecution/outputDelta'
            and message['params']['itemId'] == command_id)[0]
        completed = backend.wait_for(lambda message: message.get('method') == 'item/completed'
                                     and message['params']['item']['id'] == command_id)[0]
        assert backend.messages.index(stopped) < backend.messages.index(output) < backend.messages.index(completed)
        for message in (output, completed):
            assert message['params']['threadId'] == first_id
            assert message['params']['turnId'] == first_turn
        assert completed['params']['item']['status'] == 'completed'
        assert completed['params']['item']['exitCode'] == 0
        assert completed['params']['item']['cwd'] == str(alpha)
        assert completed['params']['item']['aggregatedOutput'] == output['params']['delta']
        assert backend.request('thread/read', {'threadId': second_id})['thread']['status'] == {
            'type': 'active', 'activeFlags': ['waitingOnApproval']}
        restored = backend.request('thread/turns/list', {'threadId': first_id})['data']
        first_history = next(turn for turn in restored if turn['id'] == first_turn)
        assert first_history['status'] == 'interrupted'
        assert any(item['id'] == command_id and item['status'] == 'completed'
                   for item in first_history['items'])
        backend.request('turn/interrupt', {'threadId': second_id, 'turnId': second_turn})
    finally:
        backend.close()


def main():
    with tempfile.TemporaryDirectory(prefix='codex-gui-qa-check-') as root:
        check_available(Path(root) / 'available')
        check_unavailable(Path(root) / 'unavailable')
        check_checkout_cwds(Path(root) / 'cwd')
        check_interleaved_approvals(Path(root) / 'interleaved')
        check_independent_client_persistence(Path(root) / 'independent-clients')
        check_late_command_after_stop(Path(root) / 'late-command-after-stop')
    print('Synthetic QA backend checks passed (review, skills, exact cwds, interleaved approvals, independent client persistence, late command after Stop).')


if __name__ == '__main__':
    main()
