"""Isolated account and settings authority shared by separate fixture processes."""

import json
import os
import time
from pathlib import Path

from .transport import ProtocolError

METHODS = {
    "account/read", "account/logout", "account/rateLimits/read", "account/usage/read",
    "config/read", "configRequirements/read",
}


def settings_request(server, method, params):
    source = Path(os.environ["CODEX_GUI_QA_SETTINGS"])
    state = json.loads(source.read_text(encoding="utf-8"))
    profile = state["profile"]
    provider = "bedrock" if profile == "bedrock" else "openai"
    email = "first@example.invalid" if profile == "first" else "second@example.invalid"
    version = "policy-" + profile
    signed_out = state.get("signedOut", False)
    is_settings = server.client_name == "codex_gui_settings"
    if method == "account/read":
        account = ({"type": "amazonBedrock", "usesCodexManagedCredentials": True}
                   if profile == "bedrock" else {"type": "chatgpt", "email": email, "planType": "plus"})
        return {"account": None if signed_out else account, "requiresOpenaiAuth": provider == "openai"}
    if not is_settings:
        raise ProtocolError(-32602, "Usage, configuration, and sign-out belong to Settings")
    if method == "config/read":
        if params != {"includeLayers": True}:
            raise ProtocolError(-32602, "Settings must read effective configuration with origins")
        value = {"model_provider": provider, "model": "settings-fixture-model",
                 "approval_policy": "never" if provider == "bedrock" else "on-request",
                 "hidden_credential": "fixture-secret-must-stay-native"}
        layer = {"name": {"type": "user", "file": str(source)}, "version": version, "config": value}
        return {"config": value, "layers": [layer], "origins": {
            "approval_policy": {"name": {"type": "enterpriseManaged"}, "version": version},
        }}
    if method == "configRequirements/read":
        return {"requirements": {"allowedApprovalPolicies": ["never"] if provider == "bedrock" else ["on-request"]}}
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
        temporary = source.with_suffix(".pending")
        temporary.write_text(json.dumps(state), encoding="utf-8")
        os.replace(temporary, source)
        return {}
    raise AssertionError(method)
