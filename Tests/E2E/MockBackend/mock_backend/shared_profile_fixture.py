"""An isolated fixture for a versioned user config and ChatGPT account shared by both clients."""
import json
import os
import time
from pathlib import Path
from tempfile import NamedTemporaryFile

from .transport import ProtocolError


METHODS = {
    "account/read", "account/logout", "account/login/start", "config/read",
    "configRequirements/read", "experimentalFeature/list", "config/batchWrite", "config/value/write",
    "thread/list",
}


def request(server, method, params):
    root = Path(os.environ["CODEX_HOME"])
    authorization = root / "fixture-account.json"
    config = root / "config.toml"
    history = root / "fixture-history.json"
    if not root.is_absolute() or not (root / ".shared-profile-fixture").is_file():
        raise ProtocolError(-32603, "The isolated fixture profile was not staged")
    if method == "thread/list":
        requested = params.get("cwd")
        if isinstance(requested, list):
            requested = requested[0]
        checkout = Path(requested)
        rows = [server.summary(thread) | {"cwd": requested}
                for thread in server.state.threads
                if checkout.samefile(thread["cwd"]) and thread["archived"] == params.get("archived", False)]
        return {"data": rows, "nextCursor": None}
    if method == "account/read":
        email = json.loads(authorization.read_text())["email"] if authorization.exists() else None
        if (root / ".hold-account-read").is_file():
            (root / ".account-read-started").touch()
            time.sleep(20)
        account = {"type": "chatgpt", "planType": "plus", "email": email} if email else None
        return {"account": account, "requiresOpenaiAuth": True}
    if method == "account/logout":
        authorization.unlink()
        return {}
    if method == "account/login/start":
        if params != {"type": "chatgpt"} or authorization.exists():
            raise ProtocolError(-32602, "The fixture expects a signed-out ChatGPT profile")
        ticket = "shared-fixture-login"

        def complete():
            replace(authorization, json.dumps({"email": "tauri@example.invalid"}) + "\n")
            server.transport.event("account/login/completed", {"loginId": ticket, "success": True})
        server.actions.append(complete)
        return {"type": "chatgpt", "loginId": ticket, "authUrl": "https://example.invalid/fixture-sign-in"}

    if method == "experimentalFeature/list":
        return {"data": [], "nextCursor": None}
    if method == "configRequirements/read":
        return {"requirements": {}}
    key, separator, raw = config.read_text(encoding="utf-8").strip().partition(" = ")
    if key != "model_verbosity" or not separator:
        raise ProtocolError(-32603, "The fixture user layer is invalid")
    prior = json.loads(raw)
    current = {key: prior}
    version = "fixture-" + prior
    layer = {"type": "user", "file": str(config)}
    if method == "config/read":
        return {"config": current, "layers": [{"name": layer, "version": version}],
                "origins": {"model_verbosity": {"name": layer, "version": version}}}

    edits = params["edits"] if method == "config/batchWrite" else [params]
    if (len(edits) != 1 or params.get("expectedVersion") != version
            or params.get("filePath", str(config)) != str(config)
            or (method == "config/batchWrite" and params.get("reloadUserConfig") is not True)):
        raise ProtocolError(409, "The captured configuration version changed")
    edit = edits[0]
    value = edit.get("value")
    if (edit.get("keyPath") != "model_verbosity" or edit.get("mergeStrategy") != "replace"
            or value not in {"low", "medium", "high"}):
        raise ProtocolError(-32602, "Unexpected fixture edit")
    replace(config, f'model_verbosity = "{value}"\n')
    assert history.is_file()
    return {"status": "ok", "version": "fixture-" + value, "filePath": str(config)}


def replace(path, content):
    with NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as temporary:
        temporary.write(content)
    os.replace(temporary.name, path)
