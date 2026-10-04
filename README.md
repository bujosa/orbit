# Orbit

**Your Macs. One clear view.**

A native macOS app for managing AI coding account access across your Macs. See which computers are reachable, which provider sessions work, and where you need to sign in. Connect Claude Code, Codex, Grok Build, and Cursor from one connection center using each provider's official login.

[Download v0.2.0 · Early access](https://github.com/bujosa/orbit/releases/tag/v0.2.0) · [User guide](Docs/user-guide.md) · [Troubleshooting](Docs/troubleshooting.md) · [Architecture](Docs/architecture.md)

![Orbit fleet dashboard with four Macs and provider connection status](Docs/images/fleet-dashboard.png)

*Real app, with Privacy mode enabled. Device names, addresses, and account details are hidden. Status is a snapshot of a running fleet.*

## One place for your coding accounts

- **Fleet health:** separate Mac, Tailscale, and T3 signals, refreshed every 60 seconds while Orbit runs.
- **Account visibility:** saved sessions, available plan labels, masked account details, and known credential expiry.
- **Verified access:** an explicit small model request distinguishes a saved login from working access. Successful results remain current for 15 minutes.
- **Official sign-in:** start login on the selected Mac, approve it in your browser, then let Orbit verify the result.
- **Guided reconnection:** reconnect accounts one at a time, with retry, skip, stop, and cancellation.
- **Local control:** a menu bar companion, optional connection alerts, trusted SSH agents, and a bundled `orbitctl` CLI.
- **Privacy mode:** hide identifying information and temporary sign-in instructions when sharing your screen.

Orbit helps you use your existing subscriptions on your Macs. Payment renewal, invoices, and remaining paid usage stay with the provider; Orbit does not manage billing or create additional usage allowances.

![Orbit connection center with verification and sign-in controls](Docs/images/connection-center.png)

## Install

The [v0.2.0 release](https://github.com/bujosa/orbit/releases/tag/v0.2.0) provides an **Apple Silicon** ZIP for **macOS 14 or later**. Extract it and move `Orbit.app` to Applications. This early-access build is ad hoc signed and **not notarized**. If macOS blocks it, review the source and build locally, or use macOS's normal app approval flow if you trust the release. Keep system security protections enabled.

Install **Node.js 22.13+** and the provider CLIs you use on each Mac. Orbit bundles the pinned Cursor SDK; Node itself and the provider CLIs are separate prerequisites. Grok support targets official **Grok Build**.

The first launch adds this Mac. For remote Macs, connect the controller and targets to your private Tailscale network, configure Remote Login and trusted SSH access, then choose **Add a Mac → Install / update agent**. Orbit checks known host keys and never silently trusts a new host. Follow the [setup guide](Docs/user-guide.md#add-a-remote-mac) for details.

Choose **Connect fleet → Check & verify fleet** to check saved sessions. This explicit action sends small requests and counts toward normal provider usage. Choose **Connect** for an account that needs approval. Passwords and MFA stay on the provider's official page.

## Build from source

Requires macOS 14+, Swift 6+, Node.js 22.13+, and npm. The UI, controller, and agent are Swift; Cursor uses its official Node SDK pinned in `Resources/cursor-runtime`.

```sh
git clone https://github.com/bujosa/orbit.git
cd orbit
swift test
bash Scripts/build-app.sh
open dist/Orbit.app
```

For a release archive and SHA-256 checksums:

```sh
bash Scripts/package-release.sh
```

See [release packaging](Docs/releasing.md) for artifact names, signing limits, and publication checks.

## Automation

The bundled controller uses the same connection policy as the UI:

```sh
Orbit.app/Contents/MacOS/orbitctl status
Orbit.app/Contents/MacOS/orbitctl connect --all
Orbit.app/Contents/MacOS/orbitctl connect "Studio"
Orbit.app/Contents/MacOS/orbitctl install-agents --all
```

`status` reads metadata without inference. `connect` explicitly verifies access, caches results privately, and exits nonzero if a selected Mac is not ready. Output is versioned JSON without credentials, sign-in challenges, emails, or private addresses. Browser sign-in stays in Orbit. Refresh the app after checks performed by an external controller.

## Privacy and availability

Credentials stay on each target Mac. Inventory and verification timestamps stay in `~/Library/Application Support/Orbit/` with private permissions, outside the app and Git. The [example inventory](Examples/fleet.example.json) contains placeholders only. Temporary sign-in codes are held in memory and cleared after the attempt.

The controller and target Macs must be powered on, awake, and connected. Remote access also requires Tailscale and SSH; T3 availability is a separate signal. Closing the window keeps the menu bar app running. Quitting Orbit or sleeping its controller stops monitoring. Orbit cannot bypass FileVault or keep an off Mac reachable, and it is not yet a separate 24/7 service.

## Project status

**0.2.0 is an early-access release.** Native challenges, cancellation, live fleet checks, and core trust boundaries have been exercised. Completed browser approval, MFA recovery, and automatic queue advancement still need broader end-to-end coverage. Developer ID signing, notarization, and automatic service recovery are future work. See the [development handoff](Docs/development-handoff.md) and [roadmap](Docs/roadmap.md).

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for validation and repository conventions. [MIT licensed](LICENSE).
