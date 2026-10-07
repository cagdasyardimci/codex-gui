#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
backend_path="${1:-$PWD/Tests/E2E/MockBackend/qa-backend}"
scenario="${2:-streaming}"
if [[ "$backend_path" != /* || ! -f "$backend_path" || ! -x "$backend_path" ]]; then
  print -u2 "Usage: $0 /absolute/path/to/compatible-qa-backend"
  exit 2
fi
./scripts/bundle.sh
qa_directory=$(mktemp -d /tmp/codex-gui-native-qa.XXXXXX)
qa_bundle="$qa_directory/CodexGUI QA.app"
cp -R .build/CodexGUI.app "$qa_bundle"
if [[ "$backend_path" == "$PWD/Tests/E2E/MockBackend/qa-backend" ]]; then
  cp -R Tests/E2E/MockBackend/. "$qa_directory/"
else
  cp "$backend_path" "$qa_directory/qa-backend"
fi
bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$qa_bundle/Contents/Info.plist")
print "QA bundle ID: $bundle_identifier"
cp -R "Tests/E2E/Fixtures/project with spaces" "$qa_directory/project with spaces"

codesign --verify --deep --strict "$qa_bundle"
git -C "$qa_directory/project with spaces" init -q --initial-branch=main
git -C "$qa_directory/project with spaces" add -- "file with spaces.swift" "activity-preview.png"
git -C "$qa_directory/project with spaces" \
  -c user.name="Codex GUI QA" -c user.email="codex-gui-qa@example.invalid" \
  -c commit.gpgSign=false -c core.hooksPath=/dev/null \
  commit -qm "test: establish native QA baseline"
open -n "$qa_bundle" --env "CODEX_EXECUTABLE=$qa_directory/qa-backend" \
  --env "CODEX_GUI_QA_SCENARIO=$scenario" \
  --env "CODEX_GUI_QA_TRACE=$qa_directory/backend-trace.jsonl" \
  --env "CODEX_GUI_QA_STATE=$qa_directory/backend-state.json" \
  --env "CODEX_GUI_WORKSPACE_ROOT=$qa_directory/task-workspaces" \
  --stderr "$qa_directory/native.log"
print "QA project: $qa_directory/project with spaces"
print "Native log: $qa_directory/native.log"
print "QA task workspaces: $qa_directory/task-workspaces"
