"""Isolated account and settings authority shared by separate fixture processes."""

import json
import os
import time
from pathlib import Path
from uuid import UUID

from . import integration_settings_fixture
from .transport import ProtocolError, UnconfirmedMutation

METHODS = {
    "account/read", "account/logout", "account/rateLimits/read", "account/usage/read",
    "config/read", "configRequirements/read", "config/value/write", "experimentalFeature/list", "model/list",
    "config/batchWrite", "memory/reset", "account/rateLimitResetCredit/consume",
} | integration_settings_fixture.METHODS


def settings_request(server, method, params):
    source = Path(os.environ["CODEX_GUI_QA_SETTINGS"])
    state = json.loads(source.read_text(encoding="utf-8"))
    profile = state["profile"]
    provider = "bedrock" if profile == "bedrock" else "openai"
    email = "first@example.invalid" if profile == "first" else "second@example.invalid"
    version = f"layer-{profile}-{state.get('version', 0)}"
    signed_out = state.get("signedOut", False)
    is_settings = server.client_name == "codex_gui_settings"
    integrations = integration_settings_fixture.Integrations(source) if profile == "second" else None
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
        if integrations:
            value.update(integrations.configuration())
        layer = {"name": {"type": "user", "file": str(source)}, "version": version, "config": value}
        origins = {
            "approval_policy": {"name": {"type": "enterpriseManaged"}, "version": version},
        }
        if integrations:
            value = integrations.managed_configuration(value)
            origins['mcp_servers."locked-fixture"'] = {"name": {"type": "enterpriseManaged"}, "version": "managed-1"}
        return {"config": value, "layers": [layer], "origins": origins}
    if not is_settings and method == "skills/list":
        return {"data": [{"cwd": cwd, "skills": [], "errors": []} for cwd in params.get("cwds", [])]}
    if not is_settings:
        raise ProtocolError(-32602, "Usage, configuration, and sign-out belong to Settings")
    if method == "configRequirements/read":
        requirements = {"allowedApprovalPolicies": ["never"] if provider == "bedrock" else ["on-request"],
                        "featureRequirements": {"local_thread_store_compression": False} if provider == "bedrock" else {}}
        if integrations:
            requirements.update(integrations.requirements())
        return {"requirements": requirements}
    if method == "experimentalFeature/list":
        features = state.get("config", {}).get("features", {})
        return {"data": [{"name": name, "enabled": features.get(name, False)}
                         for name in ("local_thread_store_compression", "memories", "browser_use", "browser_use_full_cdp_access")],
                "nextCursor": None}
    if method in {"config/value/write", "config/batchWrite"}:
        if params.get("expectedVersion") != version:
            raise ProtocolError(-32602, "Settings used a stale user layer")
        if not Path(params["filePath"]).samefile(source):
            raise ProtocolError(-32602, "Settings wrote a different profile")
        config = state.setdefault("config", {})
        if method == "config/batchWrite":
            keys = ("features.memories", "memories.generate_memories", "memories.use_memories")
            if params.get("edits") != [dict(keyPath=key, value=True, mergeStrategy="replace") for key in keys]:
                raise ProtocolError(-32602, "The memory preference must be changed atomically")
            config.setdefault("features", {})["memories"] = True
            config.setdefault("memories", {}).update(generate_memories=True, use_memories=True)
        else:
            if params.get("mergeStrategy") != "replace":
                raise ProtocolError(-32602, "Settings must replace the captured choice")
            key, value = params["keyPath"], params["value"]
            if integrations and integrations.write_configuration(key, value, config):
                pass
            elif key == "model_verbosity" and value == "high":
                config[key] = value
            elif key == "features.local_thread_store_compression" and value is True:
                config.setdefault("features", {})["local_thread_store_compression"] = value
            elif key == "memories.disable_on_external_context" and value is True:
                config.setdefault("memories", {})["disable_on_external_context"] = value
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
    if method in integration_settings_fixture.METHODS:
        if not integrations or signed_out:
            raise ProtocolError(-32602, "The integrations fixture requires its captured profile")
        return integrations.request(method, params)
    if method == "account/rateLimits/read":
        stage = reset_stage(source)
        spent = state.get("usedCredit", False) and stage != "lagging"
        limits = {"primary": {"usedPercent": 10 if spent else 100, "windowDurationMins": 300},
                  "secondary": {"windowDurationMins": 10080}, "planType": "plus"}
        response = {"accountId": "fixture-foreign" if stage == "foreign" else "fixture-" + profile,
                    "rateLimits": limits}
        if stage and not signed_out:
            credits = []
            if stage in {"offered", "expired"}:
                credits.append(dict(id="credit-expiring", title="Expiring Reset", status="available",
                                    resetType="codexRateLimits", grantedAt=0,
                                    expiresAt=2_000_000_000 if stage == "offered" else 1))
            if not spent:
                credits.append(dict(id="credit-full", title="Full Reset", status="available",
                                    resetType="codexRateLimits", grantedAt=0))
            response["rateLimitResetCredits"] = {
                "availableCount": sum(credit.get("expiresAt", 2_000_000_000) > 1 for credit in credits),
                "credits": credits,
            }
        return response
    if method == "account/rateLimitResetCredit/consume":
        attempt = UUID(params["idempotencyKey"])
        if (profile != "second" or signed_out or state.get("usedCredit") or reset_stage(source) != "valid"
                or params.get("creditId") != "credit-full" or attempt.version != 4):
            raise ProtocolError(-32602, "The reset credit is ineligible")
        state["usedCredit"] = True
        save_state(source, state)
        return {"outcome": "reset"}
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
    if method == "memory/reset":
        if params:
            raise ProtocolError(-32602, "The fake memory reset has no arguments")
        (Path(os.environ["CODEX_HOME"]) / "fixture-memory.txt").unlink()
        return {}
    raise AssertionError(method)


def save_state(source, state):
    temporary = source.with_suffix(".pending")
    temporary.write_text(json.dumps(state), encoding="utf-8")
    os.replace(temporary, source)


def reset_stage(source):
    stage = source.with_suffix(".reset")
    return stage.read_text(encoding="utf-8") if stage.is_file() else None
