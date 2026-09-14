---
name: toolchain-broken-xcode
description: How to run flutter/dart and the test suite on this dev machine, where the system Xcode is broken
metadata:
  type: feedback
---

The dev machine's Xcode at `/Applications/Xcode.app` is broken (CoreDevice/Mercury
dylib symbol mismatch: `_XPCTypeBool` not found). Anything that shells out to it
(`git` via the Xcode shim, `xcrun`, `xcodebuild`) crashes with `Abort trap: 6`.

**Why:** infra/OS state on this machine, not a project bug. `xcode-select -p` points
at the broken Xcode and can't be changed without sudo (password-gated).

**How to apply:** when running flutter/dart tooling from Bash, prepend the working
CommandLineTools binaries so a healthy `git` is found first:

    export PATH="/Library/Developer/CommandLineTools/usr/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

- `flutter test` was additionally blocked by the `objective_c` native-assets build
  hook (it runs `xcrun --show-sdk-path` under the broken Xcode). `objective_c` is a
  *transitive* dep via `path_provider_foundation >= 2.5.0` (itself only pulled in
  transitively through `flutter_secure_storage_windows` → `path_provider`).
  Fixed with a `dependency_overrides: path_provider_foundation: 2.4.1` in
  `pubspec.yaml` (last Dart-plugin release before the FFI/native-assets migration).
  Remove that override once the machine's Xcode is healthy.
- Exporting `DEVELOPER_DIR=/Library/Developer/CommandLineTools` fixes `xcrun`
  in a plain shell, but `flutter test` does NOT propagate it to build-hook
  subprocesses — so the pin above is the reliable fix, not the env var.
- Do NOT `flutter config --no-enable-native-assets`: `objective_c` (when present)
  hard-requires the feature and errors out if it's disabled.

Full device/simulator builds (`flutter build ios`) still can't run here until the
Xcode install is repaired — validate logic via `flutter test` and `flutter analyze`.
