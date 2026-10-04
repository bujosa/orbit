# Contributing to Orbit

Orbit is an early-access SwiftUI app with an on-demand Swift agent and shared controller. Read [architecture](Docs/architecture.md) before changing transport, authentication, or connection policy.

Use a focused `bujosa/` feature branch, a Conventional Commit, and a pull request targeting `main`. Keep UI and documentation in English. Never commit real inventory, credentials, account details, private addresses, or sign-in challenges. Use the placeholder example for configuration discussions.

Run the repository gates before submitting:

```sh
swift test
xcrun swift-format lint --strict --recursive Sources Tests Scripts/make-icon.swift
bash Scripts/build-app.sh
codesign --verify --deep --strict dist/Orbit.app
git diff --check
```

Review the real native UI visually; do not add automated UI snapshot or interaction tests. Core behavior and trust-boundary changes need meaningful tests. Keep the versioned agent contract and macOS 14 compatibility. Monitoring must remain free of inference and automatic sign-in; new recovery actions must be explicit.

Describe the changed behavior, base/head, exact checks and results, compatibility, and any rollout requirements in the PR. State checks that failed or did not run. Do not claim a login succeeded merely because the provider process exited successfully: access must be verified separately.
