#!/usr/bin/env python3
"""Probe message identity across a Codex CLI restart using a loopback model fixture."""

import argparse
import http.server
import json
import os
import pathlib
import queue
import subprocess
import tempfile
import threading
import uuid


class Model(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path != "/v1/responses":
            self.send_error(404)
            return
        response = {
            "id": "resp_fixture",
            "object": "response",
            "created_at": 0,
            "model": req["model"],
            "status": "completed",
            "output": [],
            "usage": {"input_tokens": 1, "output_tokens": 0, "total_tokens": 1},
        }
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        event = {"type": "response.completed", "response": response}
        self.wfile.write(f"data: {json.dumps(event)}\n\n".encode())

    def log_message(self, *_):
        pass


class AppServer:
    def __init__(self, executable, home, project):
        env = {k: v for k, v in os.environ.items() if k == "PATH" or k == "SystemRoot"}
        env.update(CODEX_HOME=str(home), HOME=str(home), USERPROFILE=str(home))
        self.process = subprocess.Popen(
            [executable, "app-server"], cwd=project, env=env,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8",
        )
        self.messages = queue.Queue()
        threading.Thread(target=self.read, daemon=True).start()
        self.notifications = []
        self.next_id = 0

    def __enter__(self):
        try:
            self.request("initialize", {
                "clientInfo": {"name": "fixture", "version": "1"},
                "capabilities": {"experimentalApi": True},
            })
            self.write({"method": "initialized", "params": {}})
        except BaseException:
            self.close()
            raise
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.process.stdout.close()
        self.process.stderr.close()

    def read(self):
        for line in self.process.stdout:
            self.messages.put(json.loads(line))
        self.messages.put(None)

    def write(self, frame):
        self.process.stdin.write(json.dumps(frame) + "\n")
        self.process.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.write({"id": self.next_id, "method": method, "params": params})
        while True:
            reply = self.receive()
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply["result"]
            self.notifications.append(reply)

    def receive(self):
        message = self.messages.get(timeout=15)
        if message is None:
            raise RuntimeError(self.process.stderr.read())
        if "id" in message and "method" in message:
            raise RuntimeError(f"Unexpected fixture server request {message['method']}")
        return message


def probe(executable, endpoint):
    with tempfile.TemporaryDirectory(prefix="codex-recovery-") as root:
        home = pathlib.Path(root, "profile")
        project = pathlib.Path(root, "checkout")
        home.mkdir()
        project.mkdir()
        home.joinpath("config.toml").write_text(f'''
model = "fixture-model"
model_provider = "fixture"
approval_policy = "never"
sandbox_mode = "read-only"
[model_providers.fixture]
name = "fixture"
base_url = "{endpoint}"
wire_api = "responses"
supports_websockets = false
requires_openai_auth = false
''', encoding="utf-8")
        expected = {}
        with AppServer(executable, home, project) as app:
            thread = app.request("thread/start", {"cwd": str(project)})["thread"]["id"]
            for _ in range(2):
                client_id = str(uuid.uuid4())
                turn = app.request("turn/start", {
                    "threadId": thread,
                    "clientUserMessageId": client_id,
                    "input": [{"type": "text", "text": "identical fixture prompt"}],
                })["turn"]["id"]
                expected[client_id] = turn
                while True:
                    note = app.receive()
                    app.notifications.append(note)
                    if note.get("method") == "turn/completed":
                        if note["params"]["turn"]["id"] != turn or note["params"]["turn"]["status"] != "completed":
                            raise RuntimeError(f"Fixture turn did not complete: {note}")
                        break
                methods = {
                    note["method"] for note in app.notifications
                    if note.get("params", {}).get("item", {}).get("clientId") == client_id
                }
                if not {"item/started", "item/completed"} <= methods:
                    raise RuntimeError(f"Missing message-ID notifications: {methods}")
        with AppServer(executable, home, project) as app:
            read = app.request("thread/read", {"threadId": thread, "includeTurns": True})
            full = app.request("thread/turns/list", {"threadId": thread, "itemsView": "full", "limit": 20})
            light = app.request("thread/turns/list", {"threadId": thread, "itemsView": "notLoaded", "limit": 20})
            for method, turns in [
                ("thread/read with turns", read["thread"]["turns"]),
                ("thread/turns/list full", full["data"]),
                ("thread/turns/list notLoaded", light["data"]),
            ]:
                matches = sorted(
                    (item["clientId"], row["id"]) for row in turns for item in row.get("items", [])
                    if item.get("type") == "userMessage" and item.get("clientId") in expected
                )
                wanted = [] if method.endswith("notLoaded") else sorted(expected.items())
                if matches != wanted:
                    raise RuntimeError(f"{method} returned unexpected message identities after restart")
        version = subprocess.check_output([executable, "--version"], text=True, timeout=10).strip()
        print(f"{version}: verified message events and both full-history reads across restart")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executables", type=pathlib.Path, nargs="+")
    args = parser.parse_args()
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Model) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            for path in args.executables:
                probe(str(path.absolute()), f"http://127.0.0.1:{server.server_port}/v1")
        finally:
            server.shutdown()
