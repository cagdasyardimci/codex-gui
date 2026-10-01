#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
./scripts/bundle.sh
qa_directory=$(mktemp -d /tmp/codex-gui-native-qa.XXXXXX)
qa_bundle="$qa_directory/CodexGUI QA.app"
cp -R .build/CodexGUI.app "$qa_bundle"
cp scripts/qa-backend.py "$qa_directory/qa-backend.py"
python3 - "$qa_bundle/Contents/Info.plist" "$qa_directory" <<'PY'
import plistlib
from pathlib import Path
import struct
import sys
import zlib
info_path = Path(sys.argv[1])
info = plistlib.loads(info_path.read_bytes())
suffix = Path(sys.argv[2]).name.rsplit('.', 1)[-1].lower()
info['CFBundleIdentifier'] = f'local.codexgui.nativeqa.{suffix}'
info['CFBundleName'] = f'CodexGUI QA {suffix}'
info_path.write_bytes(plistlib.dumps(info))
print(f"QA bundle ID: {info['CFBundleIdentifier']}")
project = Path(sys.argv[2]) / 'project with spaces'
project.mkdir()
(project / 'file with spaces.swift').write_text('// Native editor handoff fixture\nlet greeting = "Hello"\nprint(greeting)\n')
def png_chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
pixels = b''.join(b'\0' + bytes(channel for x in range(64) for channel in (45 + x * 2, 70 + y * 2, 180))
                  for y in range(64))
preview = (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 64, 8, 2, 0, 0, 0))
           + png_chunk(b'IDAT', zlib.compress(pixels)) + png_chunk(b'IEND', b''))
(project / 'activity-preview.png').write_bytes(preview)
PY
codesign --force --sign - "$qa_bundle"
git -C "$qa_directory/project with spaces" init -q --initial-branch=main
git -C "$qa_directory/project with spaces" add -- "file with spaces.swift" "activity-preview.png"
git -C "$qa_directory/project with spaces" \
  -c user.name="Codex GUI QA" -c user.email="codex-gui-qa@example.invalid" \
  -c commit.gpgSign=false -c core.hooksPath=/dev/null \
  commit -qm "test: establish native QA baseline"
open "$qa_bundle" --env "CODEX_EXECUTABLE=$qa_directory/qa-backend.py" \
  --env "CODEX_GUI_QA_STATE=$qa_directory/backend-state.json" \
  --env "CODEX_GUI_WORKSPACE_ROOT=$qa_directory/task-workspaces" \
  --stderr "$qa_directory/native.log"
print "QA project: $qa_directory/project with spaces"
print "Native log: $qa_directory/native.log"
print "QA task workspaces: $qa_directory/task-workspaces"
