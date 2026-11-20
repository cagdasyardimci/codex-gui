"""Isolated integration catalogs and settings over the installed Settings session."""

import json
import os
from pathlib import Path
from uuid import UUID

from .transport import ProtocolError

METHODS = {
    "config/mcpServer/reload", "mcpServer/oauth/login", "hooks/list", "plugin/list",
    "plugin/install", "plugin/uninstall", "marketplace/add", "marketplace/upgrade",
    "marketplace/remove", "skills/list", "skills/config/write",
}

MANAGED_MCP = "locked-fixture"
LOCAL_MCP = "fixture.local"
PLUGIN = "sample@fixture"
HOOK = "fixture.hook|file"
PRESERVED_SITE = "https://preserve.some.test:443"


class Integrations:
    def __init__(self, account):
        self.account = account
        self.path = account.with_suffix(".integrations")
        self.state = json.loads(self.path.read_text(encoding="utf-8")) if self.path.is_file() else {}

    def save(self):
        temporary = self.path.with_suffix(".integrations-pending")
        temporary.write_text(json.dumps(self.state), encoding="utf-8")
        os.replace(temporary, self.path)

    def configuration(self):
        return {
            "mcp_servers": self.state.get("mcp", {}),
            "browser_use": {
                "default_origin_policy": self.state.get("browserDefaults", {}),
                "origins": self.state.get("sites", {PRESERVED_SITE: {"downloads": "deny", "persistent_approval": False}}),
            },
        }

    @staticmethod
    def managed_configuration(value):
        return {**value, "mcp_servers": {**value["mcp_servers"], MANAGED_MCP: {"command": "managed-stdio"}}}

    @staticmethod
    def requirements():
        return {
            "featureRequirements": {"browser_use_full_cdp_access": False},
            "browserUse": {"allowHistoryAccess": False,
                           "defaultOriginPolicy": {"downloads": "deny"},
                           "origins": {"https://strict.some.test": {"downloads": "deny"}}},
        }

    def write_configuration(self, key, value, config):
        if key == "mcp_servers":
            if MANAGED_MCP in value:
                raise ProtocolError(-32602, "A managed server entered the user layer")
            entry = value.get(LOCAL_MCP)
            if entry and "command" in entry and not self.state.get("rejectedMcp"):
                self.state["rejectedMcp"] = True
                self.save()
                raise ProtocolError(-32602, "Synthetic first MCP save rejection")
            self.state["mcp"] = value
        elif key == "browser_use.origins":
            if value.get(PRESERVED_SITE) != {"downloads": "deny", "persistent_approval": False}:
                raise ProtocolError(-32602, "Site write lost its untouched sibling")
            if "https://strict.some.test" in value:
                raise ProtocolError(-32602, "A managed origin entered the user layer")
            self.state["sites"] = value
        elif key == "browser_use.default_origin_policy.access" and value == "allow":
            self.state["browserDefaults"] = {"access": value}
        elif key == "features.browser_use" and value is True:
            config.setdefault("features", {})["browser_use"] = value
        elif key == f'plugins."{PLUGIN}".enabled' and self.state.get("installed"):
            self.state["pluginEnabled"] = value
        elif key == f'hooks.state."{HOOK}".enabled':
            self.state["hookEnabled"] = value
        elif key == f'hooks.state."{HOOK}".trusted_hash' and value == "fixture-hash-v2":
            self.state["trustedHash"] = value
        else:
            return False
        self.save()
        return True

    def request(self, method, params):
        if method == "config/mcpServer/reload":
            self.state["mcpReloads"] = self.state.get("mcpReloads", 0) + 1
        elif method == "mcpServer/oauth/login":
            if params != {"name": LOCAL_MCP} or not self.state.get("mcp", {}).get(LOCAL_MCP, {}).get("url"):
                raise ProtocolError(-32602, "OAuth targeted a different MCP server")
            return {"authorizationUrl": "https://example.invalid/fixture/oauth?state=isolated"}
        elif method == "plugin/list":
            if params != {"forceRefetch": True}:
                raise ProtocolError(-32602, "The plugin catalog did not invalidate")
            return {"marketplaces": self.marketplaces()}
        elif method == "plugin/install":
            if (params.get("pluginName") != "sample" or params.get("remoteMarketplaceName") != "fixture"
                    or UUID(params["installAttemptId"]).version != 4 or self.state.get("installed")):
                raise ProtocolError(-32602, "Plugin installation used the wrong marketplace")
            self.state.update(installed=True, pluginEnabled=True)
        elif method == "plugin/uninstall":
            if params != {"pluginId": PLUGIN} or not self.state.get("installed"):
                raise ProtocolError(-32602, "Plugin removal used the wrong identity")
            self.state["installed"] = False
        elif method == "marketplace/add":
            if params != {"source": "https://example.invalid/marketplace.git", "refName": "fixture-main"}:
                raise ProtocolError(-32602, "Marketplace source or reference changed")
            self.state["marketVersion"] = 1
        elif method in {"marketplace/upgrade", "marketplace/remove"}:
            if params != {"marketplaceName": "workshop"} or not self.state.get("marketVersion"):
                raise ProtocolError(-32602, "Marketplace mutation used the wrong identity")
            self.state["marketVersion"] = 2 if method == "marketplace/upgrade" else 0
        elif method == "hooks/list":
            return {"data": [{"cwd": str(self.account.parent), "hooks": self.hooks(), "errors": [], "warnings": []}]}
        elif method in {"skills/list", "skills/config/write"}:
            return self.skills(method, params)
        else:
            raise AssertionError(method)
        self.save()
        return {}

    def marketplaces(self):
        plugins = [
            dict(id=PLUGIN, name="sample", interface={"displayName": "Fixture Plugin", "shortDescription": "Fixture commands"},
                 installed=self.state.get("installed", False), enabled=self.state.get("pluginEnabled", False),
                 installPolicy="AVAILABLE", authPolicy="ON_INSTALL", source={"source": "remote"}),
            dict(id="managed@fixture", name="managed", interface={"displayName": "Managed Plugin"},
                 installed=True, enabled=True, installPolicy="INSTALLED_BY_DEFAULT",
                 installPolicySource="WORKSPACE_SETTING", authPolicy="ON_INSTALL", source={"source": "remote"}),
        ]
        markets = [{"name": "fixture", "interface": {"displayName": "Fixture Catalog"}, "plugins": plugins}]
        if version := self.state.get("marketVersion"):
            markets.append({"name": "workshop", "path": str(self.account.parent / "market.json"),
                            "interface": {"displayName": f"Workshop v{version}"}, "plugins": []})
        return markets

    def hooks(self):
        # The provider replaces the hook after its first listing, before approval.
        current_hash = "fixture-hash-v2" if self.state.get("sawHook") else "fixture-hash-v1"
        if not self.state.get("sawHook"):
            self.state["sawHook"] = True
            self.save()
        return [
            dict(key=HOOK, eventName="preToolUse", sourcePath=str(self.account.parent / "hooks.json"),
                 enabled=self.state.get("hookEnabled", True), isManaged=False, currentHash=current_hash,
                 trustStatus="trusted" if current_hash == self.state.get("trustedHash") else "untrusted",
                 displayOrder=0, source="user", timeoutSec=30),
            dict(key="managed", eventName="postToolUse", sourcePath=str(self.account.parent / "managed.json"),
                 enabled=True, isManaged=True, currentHash="managed", trustStatus="trusted",
                 displayOrder=1, source="system", timeoutSec=30),
        ]

    def skills(self, method, params):
        root = Path(os.environ["CODEX_HOME"]) / "skills"
        user = root / "fixture" / "SKILL.md"
        if method == "skills/config/write":
            if not Path(params["path"]).samefile(user) or params["enabled"] is not False:
                raise ProtocolError(-32602, "The skill mutation used the wrong scope")
            self.state["skillEnabled"] = params["enabled"]
            self.save()
            return {"effectiveEnabled": params["enabled"]}
        if params != {"forceReload": True}:
            raise ProtocolError(-32602, "The settings skill catalog was not refreshed")
        skills = [
            dict(name="Fixture Skill", description="User skill", path=str(user),
                 enabled=self.state.get("skillEnabled", True)),
            dict(name="Bundled Skill", description="System skill", path=str(root / ".system" / "SKILL.md"), enabled=True),
            dict(name="Project Skill", description="Checkout skill",
                 path=str(self.account.parent.parent / "Settings checkout" / "SKILL.md"), enabled=True),
        ]
        return {"data": [{"cwd": str(self.account.parent), "skills": skills, "errors": []}]}
