# Troubleshooting

| What you see | What to check |
| --- | --- |
| Mac unreachable | Power and sleep state, Tailscale on both ends, Remote Login, SSH alias, and verified host key. Test the alias in Terminal without disabling host checking. |
| SSH host key rejected | Verify the fingerprint on the target through a trusted channel. Resolve the known-host entry yourself; Orbit must not silently accept a replacement key. |
| Agent unavailable or unsupported response | Use **Install / update agent** from the current Orbit build, then refresh. The target needs a compatible macOS version. |
| Tailscale available but T3 unavailable | The private network can work while T3 is stopped. Check T3 on that target and its configured endpoint. |
| Saved session, Needs verification | Choose **Verify**. Saved credentials do not prove working model access; successful checks become stale after 15 minutes. |
| Sign in required | Start a fresh official login for that provider and target. Do not copy temporary codes from an earlier attempt. |
| Code expired or cancelled | Retry to create a new challenge. Orbit cancels the old owned process; approval belongs to the account owner. |
| Usage or model access rejected | Check the provider's account entitlement, model availability, or usage limits. Signing in again does not renew paid usage. |
| Cursor runtime missing | Confirm Node.js 22.13+. On a remote target, install the pinned SDK runtime described in the user guide or use its compatible T3 CLI runtime. |
| CLI installed but not found | Check the target user's normal installation and PATH. Grok support is for official Grok Build, not a different CLI named `grok`. |
| Sign-in page or code hidden | Turn off **Privacy mode** in the connection center. |
| App shows old checks after `orbitctl connect` | Refresh or reopen Orbit to reload the private verification cache. |
| macOS blocks the release app | The early-access binary is not notarized. Build from source or use macOS's normal approval flow after reviewing the release. Keep system security protections enabled. |

## Collect useful diagnostics

Run the bundled `orbitctl status` for versioned, sanitized status metadata. It sends no inference requests. `orbitctl connect --all` explicitly sends small requests and exits nonzero when a selected Mac is not ready.

Controller output excludes credentials, temporary challenges, emails, and private addresses, but it contains your chosen device labels. Review those labels before sharing diagnostics. Never attach `devices.json`, provider caches, environment files, authorization codes, or raw provider logs to a public issue. Enable Privacy mode before sharing Orbit screenshots.

## Availability expectations

Monitoring depends on Orbit running on an awake controller. Tailscale and SSH must be available on the targets; their app windows do not need to be open. Sleeping, shut down, or FileVault-locked hosts require the corresponding system action. Orbit 0.2 does not run an independent always-on service or automatically recover a stopped provider or T3 service.
