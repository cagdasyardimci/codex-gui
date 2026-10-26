# Native QA with controlled fixtures

Run `./scripts/native-qa.sh` for manual inspection with the bundled, model-free [mock backend](mock-backend.md). Open the printed temporary project with **Open Project…**. You may pass an absolute backend executable as the first argument and a scenario name as the second. Verify which backend the QA app uses when another app instance is open.

For example, launch the bundled backend's `backend-error` scenario from the repository root:

```sh
./scripts/native-qa.sh "$PWD/Tests/E2E/MockBackend/qa-backend" backend-error
```

See [mock-backend scenarios and isolation](mock-backend.md#scenarios-and-isolation) for available scenarios and backend state reuse.

## Manual preparation and isolation

The QA copy keeps the main app's signature and bundle identifier. Follow [signing setup](../README.md#signing-setup) for certificate selection and permission continuity.

Manual QA uses temporary task workspaces and backend state, but standard preferences and default application-support stores remain shared with normal app launches. The launcher builds in this checkout's `.build` directory; follow the [build coordination safeguards](validation.md#automated-checks).

## Xcode launched-app workflow

`make test:ui` builds the workflow tools as needed and runs the Xcode UI workflow. Make exposes `UI_REPEAT` and `UI_RUN` for repeats and report reassessment:

```sh
make help:ui
make test:ui UI_REPEAT=2
make report:ui UI_RUN=/absolute/path/to/run-directory
```

For advanced options, use the Swift command from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Tests/E2E E2EWorkflow --help
```

The `--help` output lists available options, including `--backend` for a standalone backend executable.

Use full Xcode with its license and first-run setup complete. Run on an unlocked interactive desktop without competing input or clipboard writers. The UI runner needs development signing and may require macOS UI-testing or Automation permission. The workflow does not change global `xcode-select`.

Follow [validation](validation.md#automated-checks) for build coordination and source stability throughout a batch. Repetitions use separate runtime and preference state; retain every failure for review.

Unlike manual QA, each automated run isolates default task workspaces, application-support files and preferences. Appearance cases use app-scoped Light and Dark settings without changing system appearance. See the [workflow implementation](../Tests/E2E/) for launch flags and fixture preparation.

## Evidence

Each run retains a report, Xcode result and diagnostic attachments under ignored `.build/e2e/`. Captures can show surrounding applications; review artifacts before sharing them.

Read reports from expected versus observed outcome, then screen/target location, then state and backend history. Captures are sequential, and state history describes published values rather than the exact pixels drawn. Review screenshots separately and preserve failing runs. Interpret the workflow and report remaining acceptance under [validation](validation.md#native-and-live-acceptance).
