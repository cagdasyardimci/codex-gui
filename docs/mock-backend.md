# Structured mock backend

The Python backend under `Tests/E2E/MockBackend/` supplies controlled app-server responses for native QA without network requests or model calls.

## Launch

The executable entry point is `Tests/E2E/MockBackend/qa-backend`. It requires Python 3.9 or later; no packaging or backend build step is needed:

```sh
./Tests/E2E/MockBackend/qa-backend --version
./Tests/E2E/MockBackend/qa-backend app-server --stdio
```

See [native QA](native-qa.md) to launch the app with this backend or run the UI workflow, including backend and scenario selection and isolation limits.

## Scenarios and isolation

The default scenario is `streaming`. Available names are in `Tests/E2E/MockBackend/mock_backend/scenarios/`.

Give each run its own backend process and state file. Use a fresh state file when changing scenarios; prior conversations can persist across reconnects.

## Evidence limits

A fixture trace shows what the backend emitted, while app captures show what the client displayed. See [native QA](native-qa.md#evidence) for interpretation. The fixture does not establish production protocol parity, real-model behavior or live service reliability.
