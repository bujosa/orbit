# Orbit

**Your Macs. One clear view.**

A native macOS control room for your computers and AI coding accounts, built with SwiftUI and a small Swift agent. Orbit checks connectivity, T3 availability, and sessions for Claude Code, Codex, Grok Build, and Cursor, and helps you reconnect on the device that needs attention.

This project is **private during development**. Publication requires an explicit owner decision.

## What works in 0.1

- Fleet dashboard and menu bar companion, with status checks every 60 seconds while running.
- Local Macs and trusted SSH connections over Tailscale.
- Separate Mac, Tailscale, and T3 health signals.
- Session metadata, masked emails, available plan labels, and known credential expiry.
- Explicit model access checks, with results current for 15 minutes.
- Official provider sign-in in Terminal on the selected Mac.
- Optional connection/sign-in notifications and agent installation from the device menu.

**A saved login is not verified model access. Account access is not billing status.** Orbit does not invent invoice dates, remaining paid usage, or subscription renewal.

## Build

Requires macOS 14+, Swift 6+, Node.js 22.12+, and npm. The UI and agent are Swift; Cursor uses its official Node SDK, pinned in `Resources/cursor-runtime`.

```sh
swift build
swift test
bash Scripts/build-app.sh
open dist/Orbit.app
```

The bundle includes the Cursor SDK. Remote agents can reuse the SDK in an installed T3 CLI runtime. Without that runtime:

```sh
npm install --prefix "$HOME/.local/share/orbit/runtime" @cursor/sdk@1.0.31
```

Provider CLIs must already be installed on each Mac. Grok means official Grok Build in `~/.grok/bin/grok`, not the legacy Homebrew CLI. The local app is ad hoc signed; Developer ID signing and notarized distribution are future work.

## Connect a Mac

1. Connect both Macs to the same private Tailscale network.
2. Enable macOS Remote Login, configure your SSH key, and manually verify the host fingerprint.
3. Add an existing SSH alias in Orbit. Optionally override the host with its Tailscale address.
4. If the host is already trusted under a LAN address, use that address as the **known host alias**.
5. Choose **Install / update agent** from the device menu, then refresh.

Automatic checks use `BatchMode=yes` and `StrictHostKeyChecking=yes`. They never approve unknown host keys. **Open Terminal** is the explicit interactive connection action.

Inventory and verification timestamps stay in `~/Library/Application Support/Orbit/`. The directory uses `0700`; `devices.json` and `state.json` use `0600`. No real inventory belongs in Git. See [the placeholder example](Examples/fleet.example.json).

## Sign-in and renewal

Passwords and one-time codes stay in the provider browser or interactive terminal. They never enter dashboard logs.

| Provider | Official login | Session behavior |
| --- | --- | --- |
| Claude Code | `claude auth login --claudeai` | Native subscription sessions are provider-managed. Long-lived subscription tokens require replacement on expiry. |
| Codex | `codex login --device-auth` | Codex manages ChatGPT session refresh. Device login may require enabling in account settings. |
| Grok Build | `grok login --oauth --device-auth` | Grok manages OAuth refresh. Failed refresh or revocation requires sign-in. |
| Cursor | `Cursor.auth.login()` | The SDK mints a user credential, 90 days by default. Orbit displays its known expiry. |

Prefer an independent official login on each Mac. Copied credentials can share expiry, refresh state, and revocation. More computers do not create more subscriptions or separate usage allowances. Payment renewal remains with the provider.

After successful independent Claude login, Orbit can archive a recognized private `~/.t3/claude.env` shared-token file and update its recognized launcher. It refuses symlinks, permissive files, and unfamiliar launchers. The previous credential remains in a private archive on that Mac; other devices are not logged out.

Cursor supports T3's **default `cursor` instance** and current local secret-store format. Custom bindings and encrypted alternative stores are outside 0.1. Refresh T3 after login if its catalog remains stale.

Official references: [Claude authentication](https://code.claude.com/docs/en/authentication), [Codex authentication](https://learn.chatgpt.com/docs/auth), [Grok Build](https://docs.x.ai/build/overview), [Cursor SDK authentication](https://cursor.com/docs/sdk/typescript).

## Availability

Keep Orbit running in its menu bar. Each target must be powered on, awake, connected to Tailscale, and running SSH and T3. Use macOS energy and login settings intentionally for always-on hosts. FileVault may require physical unlock after reboot.

Orbit cannot keep an off/sleeping Mac reachable, bypass FileVault, restart services automatically, or renew paid subscriptions. Monitoring runs while the controller is awake; this first version is not an independent 24/7 service. Routine checks send **no model requests**. Verify access sends a tiny request and counts toward normal usage.

## Validation

```sh
swift build -c release
swift test
xcrun swift-format lint --strict --recursive Sources Tests Scripts/make-icon.swift
bash Scripts/build-app.sh
codesign --verify --strict dist/Orbit.app
git diff --check
```

Core tests cover SSH injection and trust, stale results, real access versus cached login, safe diagnostics, private inventory writes, symlink refusal, and subprocess deadlines. Native UI changes are reviewed visually.

See [architecture](Docs/architecture.md) and [roadmap](Docs/roadmap.md). MIT licensed; the repository remains private.
