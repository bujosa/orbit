# Orbit development

- This repository remains private until the owner explicitly requests publication.
- Write code, documentation, and UI copy in English.
- Never commit real device inventories, personal network addresses, account data, or credentials.
- Keep provider credentials on each device. Export only sanitized status metadata.
- Do not report a saved login as verified model access; only a successful explicit access check can do that.
- Routine monitoring must not send inference requests, trigger login, or overwrite provider credentials.
- SSH must verify known host keys and use argument arrays. New host trust is an explicit terminal action.
- Use `bujosa/` feature branches, Conventional Commits, and pull requests targeting `main`. Do not push directly to `main`.
- Run `swift build -c release`, `swift test`, formatting checks, and app-bundle validation before committing.
- Review the native UI visually. Do not add UI snapshot or automated interaction tests.
- Keep macOS 14 compatibility and a versioned agent JSON contract.
