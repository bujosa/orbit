# Development handoff

Orbit 0.2.0 is a public early-access project, published with the owner's authorization. Work on account-owner browser approvals is deferred; the local development app remains installed and running for metadata monitoring. The private inventory and verification cache are retained outside Git for a later session. Existing T3, Tailscale, provider credentials, and on-demand remote agents are preserved.

## Completed

- Native fleet dashboard, menu bar companion, and connection center.
- Privacy mode and native screenshots with device/account details hidden.
- Official managed login on the selected Mac for Claude Code, Codex, Grok Build, and Cursor.
- Explicit fleet verification and a reconnection queue with retry, skip, stop, and post-login access checks.
- Shared `orbitctl` policy, sanitized output, strict SSH trust, private local state, bounded subprocesses, and target-local Codex file-cache recovery.
- Twenty-nine passing tests plus release build, formatting, bundle-signature validation, and native visual review.
- Hosted macOS CI passed on the public feature branch, including build, all 29 tests, formatting, and app packaging; GitGuardian passed as well. Previous private-branch jobs were blocked before execution by GitHub account billing/spending limits.
- Live integration reached four Macs with Tailscale and T3 available. The latest recorded access checks passed fifteen of sixteen provider requests; one Codex connection required fresh sign-in. These are recorded results, not a guarantee of current connectivity or billing status.

## Still pending

- Account-owner approval of the remaining independent Codex logins, followed by fresh model verification.
- Completed browser-flow coverage, including MFA and expiry recovery. Challenges and cancellation were exercised; completed approval and automatic queue advancement are not yet counted as end-to-end validation.
- The production/distribution items listed in the [roadmap](roadmap.md).

## Resume locally

Build from the merged source on macOS 14+ with Swift 6+ and Node.js 22.13+:

```sh
swift test
bash Scripts/build-app.sh
ditto dist/Orbit.app "$HOME/Applications/Orbit.app"
open "$HOME/Applications/Orbit.app"
```

The retained inventory loads automatically. Connect Tailscale on the controller and targets, ensure the targets are awake, and update the remote agents from this build before resuming sign-in:

```sh
dist/Orbit.app/Contents/MacOS/orbitctl install-agents --all
dist/Orbit.app/Contents/MacOS/orbitctl status
```

In Orbit choose **Connect fleet → Reconnect needed accounts**. Use each newly displayed code on the official provider page; previous codes are expired and are never saved in the project. Orbit verifies successful sign-in before moving to the next queued account. Finish with **Check & verify fleet** for current readiness; that action sends small model requests.

The app runs only while its controller is awake and Orbit is open. On-demand remote agents do not start a background server. Reinstalling does not renew a paid subscription or create another usage allowance.
