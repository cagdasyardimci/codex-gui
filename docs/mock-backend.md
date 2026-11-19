# Structured mock backend

The Python backend under `Tests/E2E/MockBackend/` supplies controlled app-server responses for native QA without network requests or model calls.

## Launch

The executable entry point is `Tests/E2E/MockBackend/qa-backend`. It requires Python 3.9 or later; no packaging or backend build step is needed:

```sh
./Tests/E2E/MockBackend/qa-backend --version
./Tests/E2E/MockBackend/qa-backend app-server --stdio
```

See [native QA](native-qa.md) to launch the app with this backend or run the UI workflow, including backend and scenario selection and isolation limits.

### Portable desktop fixture

The [desktop launcher](../desktop/fixtures/mock_backend.py) runs the same entry point through Python so it works across desktop operating systems. Give each run a private checkout and state directory. To verify fixture launch and isolation, run `python -m unittest discover -s desktop/fixtures -v` from the repository root with Python 3.9 or later.

## Scenarios and isolation

Available scenarios are in [the scenario directory](../Tests/E2E/MockBackend/mock_backend/scenarios/).

Give each run its own backend process and state file. Use a fresh state file when changing scenarios; prior conversations can persist across reconnects.

For fixture-trace and capture interpretation, follow [native QA evidence review](native-qa.md#evidence).
