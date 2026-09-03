# In-menu updates

Repository: https://github.com/brewstercm/Kanto-Johto-National-Dex

Place this folder's **contents** at the repository root, including `.github`.
Do not nest them in the version-named folder. `manifest.json`, `main.lua`,
`assets`, `data`, and `tools` must be at the repository root.

The release workflow runs on pushes to `main` or manually from GitHub Actions.
It validates the authored encounter/quest data and publishes a release using
the manifest version, with a ZIP named `<id>-<version>.zip`. The manifest and
entry point are directly at the ZIP root, as required by the updater.

For each future release, update `manifest.json` to a higher version and push
the maintained changes. Existing releases are not overwritten. Never change
the mod ID: it is also the identity of existing mod save state.

Users must import version 0.9.12 once to acquire the GitHub metadata. Later
published versions are available through the mod menu's Update/Versions UI.
The repository must remain public, with an installable ZIP release asset.

Local packaging (from this directory):

```text
python tools/build_release.py --output ..
```

GitHub authentication is required to push files; the workflow uses GitHub's
temporary repository token to publish releases. No credentials belong here.
