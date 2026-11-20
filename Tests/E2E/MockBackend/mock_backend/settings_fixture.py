"""Isolated account and settings authority shared by separate fixture processes."""

import json
import os
import time
from pathlib import Path

from .transport import ProtocolError, UnconfirmedMutation

METHODS = {
    "account/read", "account/logout", "account/rateLimits/read", "account/usage/read",
    "config/read", "configRequirements/read", "config/value/write", "experimentalFeature/list", "model/list",
}


def settings_request(server, method, params):
    source = Path(os.environ["CODEX_GUI_QA_SETTINGS"])
    state = json.loads(source.read_text(encoding="utf-8"))
    profile = state["profile"]
    provider = "bedrock" if profile == "bedrock" else "openai"
    email = "first@example.invalid" if profile == "first" else "second@example.invalid"
    version = f"layer-{profile}-{state.get('version', 0)}"
    signed_out = state.get("signedOut", False)
    is_settings = server.client_name == "codex_gui_settings"
    if method == "account/read":
        account = ({"type": "amazonBedrock", "usesCodexManagedCredentials": True}
                   if profile == "bedrock" else {"type": "chatgpt", "email": email, "planType": "plus"})
        return {"account": None if signed_out else account, "requiresOpenaiAuth": provider == "openai"}
    if method == "model/list":
        model = server.desktop_model("fixture-default", False)
        model.update(isDefault=True, defaultReasoningEffort="medium", supportedReasoningEfforts=[
            {"reasoningEffort": "medium", "description": "Medium"},
            {"reasoningEffort": "minimal", "description": "Minimal"},
        ])
        return {"data": [model], "nextCursor": None}
    if method == "config/read":
        if params.get("includeLayers") is not is_settings:
            raise ProtocolError(-32602, "Settings must read effective configuration with origins")
        value = {"model_provider": provider, "model": "fixture-default",
                 "review_model": "settings-fixture-model",
                 "approval_policy": "never" if provider == "bedrock" else "on-request",
                 "model_verbosity": "medium", "model_reasoning_summary": "auto",
                 "sandbox_mode": "workspace-write", "hidden_credential": "fixture-secret-must-stay-native"}
        value.update(state.get("config", {}))
        layer = {"name": {"type": "user", "file": str(source)}, "version": version, "config": value}
        return {"config": value, "layers": [layer], "origins": {
            "approval_policy": {"name": {"type": "enterpriseManaged"}, "version": version},
        }}
    if not is_settings:
        raise ProtocolError(-32602, "Usage, configuration, and sign-out belong to Settings")
    if method == "configRequirements/read":
        return {"requirements": {"allowedApprovalPolicies": ["never"] if provider == "bedrock" else ["on-request"],
                                 "featureRequirements": {"local_thread_store_compression": False} if provider == "bedrock" else {}}}
    if method == "experimentalFeature/list":
        return {"data": [{"name": "local_thread_store_compression",
                          "enabled": state.get("config", {}).get("features", {}).get("local_thread_store_compression", False)}],
                "nextCursor": None}
    if method == "config/value/write":
        if params.get("expectedVersion") != version or params.get("mergeStrategy") != "replace":
            raise ProtocolError(-32602, "Settings used a stale user layer")
        if not Path(params["filePath"]).samefile(source):
            raise ProtocolError(-32602, "Settings wrote a different profile")
        key, value = params["keyPath"], params["value"]
        config = state.setdefault("config", {})
        if key == "model_verbosity" and value == "high":
            config[key] = value
        elif key == "features.local_thread_store_compression" and value is True:
            config.setdefault("features", {})["local_thread_store_compression"] = value
        elif key == "model_reasoning_summary" and value == "concise":
            config[key] = "detailed"
            state["version"] = state.get("version", 0) + 2
            save_state(source, state)
            raise UnconfirmedMutation()
        else:
            raise ProtocolError(-32602, "Settings wrote a managed or unexpected field")
        state["version"] = state.get("version", 0) + 1
        save_state(source, state)
        return {"status": "ok", "filePath": str(source), "version": f"layer-{profile}-{state['version']}"}
    if method == "account/rateLimits/read":
        return {"accountId": "fixture-" + profile,
                "rateLimits": {"primary": {"usedPercent": 100, "windowDurationMins": 300},
                               "secondary": {"windowDurationMins": 10080}, "planType": "plus"}}
    if method == "account/usage/read":
        if profile == "delayed":
            source.with_name("settings-usage-started").touch()
            time.sleep(0.8)
        return {"dailyUsageBuckets": [
            {"startDate": "2026-10-29", "tokens": 250},
            {"startDate": "2026-10-28", "tokens": 0},
            {"startDate": "2026-10-27"},
        ]}
    if method == "account/logout":
        if profile != "second" or signed_out:
            raise ProtocolError(-32602, "The captured account changed before sign-out")
        state["signedOut"] = True
        save_state(source, state)
        return {}
    raise AssertionError(method)


def save_state(source, state):
    temporary = source.with_suffix(".pending")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    os.replace(temporary, source)
