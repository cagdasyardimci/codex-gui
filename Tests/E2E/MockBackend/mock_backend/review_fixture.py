"""Run captured review targets with separate inline and detached turns."""

import threading
import time

from .transport import ProtocolError


class ReviewRun:
    def __init__(self, server, thread, target, detached):
        self.server = server
        self.thread = thread
        self.target = target
        self.detached = detached
        self.cancelled = threading.Event()
        self.turn = {
            "id": server.state.identity("review-turn"), "status": "inProgress", "items": [],
            "startedAt": int(time.time()),
        }
        thread["turns"].append(self.turn)

    def start(self):
        server = self.server
        thread_id, turn_id = self.thread["id"], self.turn["id"]
        server.transport.event("turn/started", {"threadId": thread_id, "turn": self.turn})
        entered = {"type": "enteredReviewMode", "id": turn_id + "-enter", "review": "Review fixture"}
        server.transport.event("item/started", {"threadId": thread_id, "turnId": turn_id, "item": entered})
        threading.Thread(target=self.finish, daemon=True).start()

    def finish(self):
        interrupted = self.cancelled.wait(25 if self.detached else 0.75)
        server = self.server
        with server.lock:
            thread_id, turn_id = self.thread["id"], self.turn["id"]
            kind = self.target["type"]
            message = {
                "uncommittedChanges": "Reviewed the captured uncommitted changes.",
                "baseBranch": "Reviewed the captured base branch.",
                "commit": "Reviewed the captured commit.",
                "custom": "Reviewed the captured instructions.",
            }[kind]
            if interrupted:
                message = "Stopped the detached review."
            item = {"type": "exitedReviewMode", "id": turn_id + "-exit", "review": message}
            self.turn["items"].append(item)
            self.turn.update(status="interrupted" if interrupted else "completed", completedAt=int(time.time()))
            server.active.pop(thread_id, None)
            server.state.save()
            server.transport.event("item/completed", {"threadId": thread_id, "turnId": turn_id, "item": item})
            server.transport.event("turn/completed", {"threadId": thread_id, "turn": self.turn})


def start_review(server, params):
    source = server.thread(params["threadId"])
    target, delivery = params["target"], params["delivery"]
    kind = target.get("type")
    keys = {"uncommittedChanges": {"type"}, "baseBranch": {"type", "branch"},
            "commit": {"type", "sha"}, "custom": {"type", "instructions"}}
    if set(params) != {"threadId", "target", "delivery"} or kind not in keys or set(target) != keys[kind]:
        raise ProtocolError(-32602, "Review target changed shape")
    if delivery not in {"inline", "detached"} or source["id"] in server.active:
        raise ProtocolError(-32002, "Review requires an idle captured source")
    thread = source
    if delivery == "detached":
        thread = {
            "id": server.state.identity("detached-review"), "name": "Detached Fixture Review",
            "preview": "Review the captured changes.", "cwd": source["cwd"], "archived": False, "turns": [],
        }
        server.state.threads.append(thread)
    run = ReviewRun(server, thread, target, delivery == "detached")
    server.active[thread["id"]] = run
    server.actions.append(run.start)
    return {"reviewThreadId": thread["id"], "turn": run.turn}
