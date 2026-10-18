# Native QA with controlled fixtures

Run `./scripts/native-qa.sh` for manual inspection with the bundled, model-free [mock backend](mock-backend.md). Open the printed temporary project with **Open Project…**. You may pass an absolute backend executable as the first argument and a scenario name as the second. Verify which backend the QA app uses when another app instance is open.

## Manual preparation and isolation

The QA copy keeps the main app's signature and bundle identifier. With a consistent Apple Development certificate, compatible builds can retain macOS permission grants; ad hoc signing may require approval again after rebuilds. See [signing setup](../README.md#signing-setup) for certificate selection and the certificate-free fallback. Those grants remain under the user's control; notification banner delivery requires native observation.

Manual QA uses temporary task workspaces and backend state, but standard preferences and default application-support stores remain shared with normal app launches. The launcher builds in this checkout's `.build` directory; coordinate other builds using it.

## Xcode launched-app workflow

`make test:ui` builds the workflow tools as needed and runs the Xcode UI workflow.
Make exposes `UI_REPEAT` and `UI_RUN` for repeats and report reassessment:

```sh
make help:ui
make test:ui UI_REPEAT=2
make report:ui UI_RUN=/absolute/path/to/run-directory
```

Use `make help` or `make help:ui` for commands. For advanced options, use the Swift command
from the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Tests/E2E E2EWorkflow --help
```

The `--help` output lists available options. Test runs and report reassessment share the checkout's `.build/e2e/workflow.lock` while exporting evidence or building workflow tools. A competing workflow exits before replacing artifacts.

Use full Xcode with its license and first-run setup complete. Run on an unlocked interactive desktop without competing input. The UI runner needs development signing and may require macOS UI-testing or Automation permission. The workflow does not change global `xcode-select`.

Coordinate other builds using this checkout and keep the source stable throughout a batch. Repetitions use separate runtime and preference state; retain every failure for review.

Unlike manual QA, each automated run isolates default task workspaces, application-support files and preferences.

## Evidence

Each run retains a report, Xcode result and diagnostic attachments under ignored `.build/e2e/`. Captures can show surrounding applications; review artifacts before sharing them.

Other desktop input or clipboard writers can disrupt the workflow.

Read reports from expected versus observed outcome, then screen/target location, then state and backend history. Captures are sequential, and state history describes published values rather than the exact pixels drawn. A passing workflow establishes only the exercised behavior with this synthetic backend. Review screenshots separately, preserve failing runs, and report live-backend, notification-delivery and minimum-macOS evidence under [validation](validation.md#native-and-live-acceptance).
