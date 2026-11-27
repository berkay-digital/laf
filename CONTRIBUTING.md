# Contributing

Bug reports and pull requests are welcome. For a larger change, open an issue first so we can agree on the approach.

## Building

- **macOS:** `./macos/build.sh` builds and installs `~/Applications/Laf.app`. Set `INSTALL=0` to only build into `macos/build/`. Logs are in `~/Library/Application Support/Laf/`.
- **Windows:** run `windows/setup.ps1`, or start `laf.pyw` from a Python 3.12 environment with `windows/requirements.txt` installed.

## Tests

`python windows/laf.pyw --selftest` checks the word matching, prompt helpers and JSON parsing on any OS. With an API key in the settings file, it also sends a few sample dictations to the model and prints the results.

## Keeping the two apps in sync

The Mac app (`macos/App/main.swift`) and the Windows app (`windows/laf.pyw`) share the cleanup prompt, the learning prompt and the `memory.json` format. If you change one of those, change both, so word lists keep working across machines.

## Dependencies

`windows/requirements.txt` is generated from `windows/requirements.in`:

```sh
uv pip compile windows/requirements.in --python-platform windows --python-version 3.12 --no-header --no-annotate -o windows/requirements.txt
```
