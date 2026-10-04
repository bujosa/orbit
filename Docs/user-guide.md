# User guide

## Requirements

- macOS 14 or later. The downloadable 0.2.0 binary targets Apple Silicon; other architectures need a local build.
- Node.js 22.13+ available in a normal install location or the Mac's configured PATH.
- Official Claude Code, Codex, and Grok Build CLIs for the providers you use. Cursor uses its official SDK, bundled on the controller.
- A provider account with access to the requested model. A saved account session alone does not prove model access.

Download the [early-access release](https://github.com/bujosa/orbit/releases/tag/v0.2.0), extract the ZIP, and move the app to Applications. It is ad hoc signed, not notarized. You can instead build from the tagged source using the README instructions.

## Add a remote Mac

1. Connect both Macs to the same private Tailscale network. Tailscale runs on the controller and target, even when its window is closed.
2. On the target, enable **System Settings → General → Sharing → Remote Login** for your intended user.
3. Configure a key-based SSH alias on the controller. Manually check the target's host fingerprint through a trusted channel before accepting it in Terminal. Orbit does not approve unknown hosts.
4. Confirm that `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes studio true` succeeds for your alias.
5. In Orbit choose **Add a Mac**. Enter a display name and existing SSH alias. Optionally set a Tailscale address and the target's T3 HTTPS URL.
6. If the same target key is already trusted under another address, set **Known host alias** to that existing known-host entry. This selects the trusted key; it does not skip verification.
7. From the Mac's device menu choose **Install / update agent**, then refresh.

The agent is an on-demand Swift executable installed in the target user's private tooling directory. It does not open a network listener or install a daemon. Update it whenever you update Orbit, especially before using a new sign-in protocol.

Remote Cursor needs its SDK runtime. An installed T3 CLI runtime can supply it; otherwise install the pinned runtime on that target:

```sh
npm install --prefix "$HOME/.local/share/orbit/runtime" @cursor/sdk@1.0.31
```

## Read the dashboard

| Signal | Meaning |
| --- | --- |
| Mac online | Local or trusted SSH metadata check succeeded. |
| Tailscale | The agent reports its private network connection. |
| T3 | The target's T3 availability check succeeded. |
| Saved session | Provider credentials are present; model access has not necessarily been tested. |
| Verified | A small explicit model request succeeded within the last 15 minutes. |
| Needs verification | No current successful access result is available. |
| Sign in required | The provider rejected authentication or no usable login exists. |
| Ready | Mac, Tailscale, T3, and all four provider access checks succeeded. |

Routine refresh runs every 60 seconds while Orbit is open and the controller is awake. It sends no model requests and does not sign in automatically. **Verify** and **Check & verify fleet** send small model requests and may count toward normal usage. Authentication rejection remains actionable until a new successful check; expiry of the 15-minute success window does not erase it.

## Connect your accounts

Open **Connect fleet**, then select **Connect** or **Sign in** beside the provider on the intended Mac. Orbit launches that provider's official flow through the trusted target agent.

1. Choose **Open provider sign-in** and approve your existing account in the browser.
2. For Codex and Grok, enter Orbit's temporary device code on that page. For Claude, paste the one-time authorization code into Orbit if requested. Cursor detects browser completion automatically.
3. Complete any MFA or account approval on the official page. Orbit never asks for your password.
4. Wait for Orbit's post-login access check. Only successful model access marks the provider verified.

Turn **Privacy mode** off to see the temporary sign-in instructions. Codes and challenge URLs stay in memory and are not saved in inventory, diagnostics, or controller output.

**Reconnect needed accounts** creates a queue. It completes one login and access check before starting the next. Failure or expiry pauses the queue; choose retry or skip. **Stop queue** cancels the owned attempt and clears pending items. Cancelling, expiry, or quitting Orbit stops its login process. Codex file-cache recovery can restore a previous cache removed by an unsuccessful attempt, while preserving newly written or externally changed credentials. That recovery cannot guarantee the provider still accepts the old session.

Each Mac should have an independent official login. More devices share your provider's existing entitlement and usage policy. Orbit does not purchase or renew subscriptions. Provider refresh behavior remains provider-owned.

## Privacy mode and notifications

Enable **Privacy mode** before screen sharing. The dashboard and connection center replace device names with numbered Macs, hide addresses and account details, and hide temporary login instructions. New Orbit notifications use the hidden device labels too. It is a presentation setting: it does not rewrite inventory, erase prior notifications, or hide the contents of other apps or Terminal.

**Connection alerts** is optional and uses macOS notification permission. Alerts cover lost connectivity, unavailable T3, and authentication that needs attention. Normal refresh does not start recovery actions.

## Local data and updates

Orbit stores `devices.json` and `state.json` in `~/Library/Application Support/Orbit/`. The directory uses `0700` permissions and those files use `0600`. Provider credentials remain on the device that owns them. Keep inventory, private addresses, credentials, and sign-in screenshots out of issues and repositories.

Quit Orbit before replacing its app bundle. Your Application Support inventory remains available after an update. Open the updated app, update each remote agent, then refresh. Closing its main window keeps the menu bar companion running; **Quit Orbit** stops monitoring. FileVault may require a physical unlock and user login after a target reboot.

For command-line status, explicit verification, and agent installation, use the commands in the [README](../README.md#automation). For problems, see [troubleshooting](troubleshooting.md).
