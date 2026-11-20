#!/usr/bin/env python3
"""Check the first desktop workflow against schemas from the pinned Codex executables."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


# These inventories cover the first installed coding workflow. Extend them with
# the owning feature when the adapter adopts additional protocol operations.
CLIENT_REQUESTS = {
    "initialize": ("clientInfo", "capabilities"),
    "account/read": ("refreshToken",),
    "account/logout": (),
    "account/rateLimits/read": (),
    "account/usage/read": (),
    "config/read": ("includeLayers", "cwd"),
    "configRequirements/read": (),
    "model/list": ("cursor", "limit"),
    "thread/list": ("cwd", "archived", "cursor", "limit"),
    "thread/read": ("threadId", "includeTurns"),
    "thread/archive": ("threadId",),
    "thread/unarchive": ("threadId",),
    "thread/delete": ("threadId",),
    "thread/turns/list": ("threadId", "itemsView", "cursor", "limit"),
    "thread/queue/list": ("threadId", "cursor", "limit"),
    "thread/queue/add": ("threadId", "input", "clientUserMessageId"),
    "thread/queue/update": ("threadId", "queuedSubmissionId", "input"),
    "thread/queue/delete": ("threadId", "queuedSubmissionId"),
    "thread/queue/start": ("threadId", "queuedSubmissionId"),
    "thread/queue/reorder": ("threadId", "queuedSubmissionIds"),
    "thread/start": ("cwd", "ephemeral", "approvalPolicy", "sandbox", "baseInstructions", "config", "model"),
    "thread/name/set": ("threadId", "name"),
    "thread/unsubscribe": ("threadId",),
    "feedback/upload": ("classification", "threadId", "includeLogs", "tags"),
    "review/start": ("threadId", "target", "delivery"),
    "thread/resume": ("threadId", "excludeTurns"),
    "turn/start": ("threadId", "input", "cwd", "clientUserMessageId", "effort", "outputSchema"),
    "turn/steer": ("threadId", "expectedTurnId", "input", "clientUserMessageId"),
    "turn/interrupt": ("threadId", "turnId"),
    "windowsSandbox/readiness": (),
    "windowsSandbox/setupStart": ("mode", "cwd"),
}
SERVER_REQUESTS = {
    "item/commandExecution/requestApproval": (
        "threadId", "turnId", "itemId", "command", "cwd", "kind",
        "networkApprovalContext", "additionalPermissions", "availableDecisions",
    ),
    "item/fileChange/requestApproval": ("threadId", "turnId", "itemId"),
    "item/permissions/requestApproval": ("threadId", "turnId", "itemId", "permissions"),
    "item/tool/requestUserInput": ("threadId", "turnId", "itemId", "isBlocking", "questions"),
}
SERVER_NOTIFICATIONS = {
    "thread/queue/changed": ("threadId",),
    "turn/started": ("threadId", "turn"),
    "turn/completed": ("threadId", "turn"),
    "item/agentMessage/delta": ("threadId", "turnId", "itemId", "delta"),
    "item/completed": ("threadId", "turnId", "item"),
    "serverRequest/resolved": ("threadId", "requestId"),
    "windowsSandbox/setupCompleted": ("mode", "success", "error"),
}
INCOMING_RESPONSES = {
    "v1/InitializeResponse": ("userAgent", "codexHome", "platformFamily", "platformOs"),
    "v2/GetAccountResponse": ("account", "requiresOpenaiAuth"),
    "v2/LogoutAccountResponse": (),
    "v2/GetAccountRateLimitsResponse": ("rateLimits", "rateLimitsByLimitId", "accountId"),
    "v2/GetAccountTokenUsageResponse": ("dailyUsageBuckets",),
    "v2/ConfigReadResponse": ("config", "origins", "layers"),
    "v2/ConfigRequirementsReadResponse": ("requirements",),
    "v2/ModelListResponse": ("data", "nextCursor"),
    "v2/ThreadListResponse": ("data", "nextCursor"),
    "v2/ThreadReadResponse": ("thread",),
    "v2/ThreadArchiveResponse": (),
    "v2/ThreadUnarchiveResponse": ("thread",),
    "v2/ThreadDeleteResponse": (),
    "v2/FeedbackUploadResponse": ("threadId",),
    "v2/ReviewStartResponse": ("reviewThreadId", "turn"),
    "v2/ThreadTurnsListResponse": ("data", "nextCursor"),
    "v2/ThreadQueueListResponse": ("data", "nextCursor"),
    "v2/ThreadQueueAddResponse": ("queuedSubmission",),
    "v2/ThreadQueueUpdateResponse": ("queuedSubmission",),
    "v2/ThreadQueueDeleteResponse": ("deleted",),
    "v2/ThreadQueueStartResponse": ("turn",),
    "v2/ThreadQueueReorderResponse": (),
    "v2/ThreadStartResponse": ("thread", "cwd"),
    "v2/ThreadResumeResponse": ("thread", "cwd"),
    "v2/TurnStartResponse": ("turn",),
    "v2/TurnSteerResponse": ("turnId",),
    "v2/TurnInterruptResponse": (),
    "v2/WindowsSandboxReadinessResponse": ("status",),
    "v2/WindowsSandboxSetupStartResponse": ("started",),
}
OUTGOING_RESPONSES = {
    "CommandExecutionRequestApprovalResponse": ("decision",),
    "FileChangeRequestApprovalResponse": ("decision",),
    "PermissionsRequestApprovalResponse": ("permissions", "scope"),
    "ToolRequestUserInputResponse": ("answers",),
}
REMOTE_ACCESS_TARGET = {
    "remoteControl/enable": (),
    "remoteControl/status/read": (),
}


class SchemaMismatch(ValueError):
    pass


def load_schema(root, name):
    return json.loads((root / (name + ".json")).read_text(encoding="utf-8"))


def check_fields(schema, fields, where, outbound=False):
    absent = set(fields) - set(schema.get("properties", {}))
    if absent:
        raise SchemaMismatch(f"{where} is missing fields {', '.join(sorted(absent))}")
    if outbound:
        uncovered = set(schema.get("required", [])) - set(fields)
        if uncovered:
            raise SchemaMismatch(f"{where} needs additional required fields {', '.join(sorted(uncovered))}")


def check_methods(root, document_name, methods, *, request, outbound=False):
    document = load_schema(root, document_name)
    methods_in_schema = {}
    for branch in document["oneOf"]:
        for method in branch["properties"]["method"]["enum"]:
            methods_in_schema[method] = branch

    for method, fields in methods.items():
        if method not in methods_in_schema:
            raise SchemaMismatch(f"{document_name} is missing {method}")
        branch = methods_in_schema[method]
        if ("id" in branch.get("required", [])) != request:
            raise SchemaMismatch(f"{method} changed its envelope ID requirement")
        params = branch["properties"].get("params", {})
        if "$ref" in params:
            params = document["definitions"][params["$ref"].split("/")[-1]]
        check_fields(params, fields, method, outbound=outbound)


def check_schema(root, *, remote_access_target):
    check_methods(root, "ClientRequest", CLIENT_REQUESTS, request=True, outbound=True)
    check_methods(root, "ClientNotification", {"initialized": ()}, request=False, outbound=True)
    check_methods(root, "ServerRequest", SERVER_REQUESTS, request=True)
    check_methods(root, "ServerNotification", SERVER_NOTIFICATIONS, request=False)

    for name, fields in INCOMING_RESPONSES.items():
        check_fields(load_schema(root, name), fields, name)
    for name, fields in OUTGOING_RESPONSES.items():
        check_fields(load_schema(root, name), fields, name, outbound=True)
    queued_submission = load_schema(root, "v2/ThreadQueueListResponse")["definitions"]["QueuedSubmission"]
    check_fields(queued_submission, ("id", "clientUserMessageId", "input"), "QueuedSubmission")

    ids = {variant["type"] for variant in load_schema(root, "RequestId")["anyOf"]}
    if ids != {"integer", "string"}:
        raise SchemaMismatch(f"RequestId must support exactly integer and string, found {sorted(ids)}")

    init = load_schema(root, "v1/InitializeParams")["definitions"]
    check_fields(init["ClientInfo"], ("name", "title", "version"), "ClientInfo", outbound=True)
    check_fields(init["InitializeCapabilities"], ("experimentalApi", "requestAttestation"),
                 "InitializeCapabilities", outbound=True)

    if remote_access_target:
        check_methods(root, "ClientRequest", REMOTE_ACCESS_TARGET, request=True, outbound=True)
        check_fields(load_schema(root, "v2/RemoteControlStatusReadResponse"),
                     ("status", "serverName", "installationId"), "RemoteControlStatusReadResponse")


def check_executable(executable, version, *, remote_access_target=False):
    executable = str(executable.absolute())
    with tempfile.TemporaryDirectory(prefix="codex-gui-schema-") as temporary:
        root = Path(temporary)
        codex_home = root / "codex-home"
        codex_home.mkdir()
        environment = {**os.environ, "CODEX_HOME": str(codex_home)}
        report = subprocess.run(
            [executable, "--version"], env=environment, capture_output=True, text=True,
            encoding="utf-8", check=True, timeout=30
        ).stdout.strip()
        if not report.split() or report.split()[-1] != version:
            raise SchemaMismatch(f"{executable} must report {version}, received {report!r}")
        output = root / "schema"
        subprocess.run(
            [executable, "app-server", "generate-json-schema", "--experimental", "--out", str(output)],
            env=environment, check=True, timeout=90
        )
        check_schema(output, remote_access_target=remote_access_target)
        print(f"{report}: first-workflow schema contract passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--remote-access-target", type=Path, required=True)
    args = parser.parse_args()
    try:
        check_executable(args.baseline, "0.153.2")
        check_executable(args.remote_access_target, "0.163.0", remote_access_target=True)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f"App-server schema check failed: {error}\n")


if __name__ == "__main__":
    main()
