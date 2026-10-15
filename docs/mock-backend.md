# Structured mock backend

The Python backend under `Tests/E2E/MockBackend/` supplies controlled app-server responses for native QA without network requests or model calls.

## Launch

The executable entry point is `Tests/E2E/MockBackend/qa-backend`. It requires Python 3.9 or later; no packaging or backend build step is needed:

```sh
./Tests/E2E/MockBackend/qa-backend --version
./Tests/E2E/MockBackend/qa-backend app-server --stdio
```

Run `make test:ui` for automated UI checks or `./scripts/native-qa.sh` for manual inspection. See [native QA](native-qa.md) for workflows and isolation limits.

To select another manual scenario, pass its name as the launcher's second argument, for example `./scripts/native-qa.sh "$PWD/Tests/E2E/MockBackend/qa-backend" backend-error`. Available names are in `Tests/E2E/MockBackend/mock_backend/scenarios/`. The Swift workflow accepts a standalone executable with `--backend`.

## Scenarios and isolation

The default scenario is `streaming`.

Give each run its own backend process and state file. Use a fresh state file when changing scenarios; prior conversations can persist across reconnects.

## Evidence limits

A fixture trace shows what the backend emitted, while app captures show what the client displayed. See [native QA](native-qa.md#evidence) for interpretation. The fixture does not establish production protocol parity, real-model behavior or live service reliability.
