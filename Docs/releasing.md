# Release packaging

The current distribution is early access: ad hoc signed, not Developer ID signed or notarized. The downloadable 0.2.0 build is Apple Silicon and requires macOS 14+, Node.js 22.13+, and separately installed provider CLIs. Do not describe it as a universal or notarized app.

## Prepare

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` on a feature branch. Write release notes and check all download URLs.
2. Capture the real app with Privacy mode enabled. Review images for names, addresses, account data, and authorization challenges. Screenshots belong in `Docs/images/`; do not modify private inventory to create a demo.
3. Run `swift test`, the README formatting command, the app build, bundle signature verification, and `git diff --check`. Review source and history for credentials before public publication. Report hosted checks accurately.
4. Merge the reviewed PR through the normal repository rules. Check out the exact clean merged commit before building the release.

## Package

On the intended macOS architecture:

```sh
bash Scripts/package-release.sh
cd dist/release
shasum -a 256 -c SHA256SUMS
```

The script builds the release app, verifies its ad hoc signature, checks all Swift executable architectures, then creates `Orbit-v<VERSION>-macos-<ARCH>.zip` and `SHA256SUMS`. The ZIP contains only the app bundle; inventory and provider credentials are stored outside it. Confirm the archive contents before uploading.

Create the version tag against the exact merged commit and publish the ZIP and checksum file as a GitHub **prerelease**. Include the tagged source commit, architecture, requirements, signing limitations, setup docs, and known incomplete validation in the notes. Releases must not contain personal inventory or logs.

## Install and smoke check

Quit the existing Orbit process before replacing its bundle. Move the new app to Applications and launch it. Existing Application Support inventory remains intact. Check the main window and menu bar, a metadata refresh, and Privacy mode. Update on-demand remote agents from the same build before further managed sign-in. Do not initiate account-owner approvals as part of packaging.
