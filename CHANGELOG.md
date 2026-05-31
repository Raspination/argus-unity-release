# Changelog

All notable changes to `com.argus.profiler` are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_Nothing yet — file issues at <https://github.com/Raspination/argus-unity-release/issues>._

---

## [2.0.3] — 2026-05-31

### Added
- **Offline-toggle gate.** The "Offline" checkbox in the Argus Control window is now disabled until the user has successfully connected to the dashboard at least once. Stops first-time installers from hiding the dashboard onboarding flow behind a stale local-capture mode. Per-machine sticky flag (EditorPrefs `ArgusHasEverConnected`) — survives Editor restarts; reset by **Tools → Argus → Clear Stored Data**.
- **`ArgusReleaser.PublishToGitHub` Editor menu** for operators. `Tools → Argus → Publish to GitHub` commits + tags + pushes the latest export to the distribution repo in one click. Default remote configurable per-machine via EditorPrefs.
- **CHANGELOG.md + SECURITY.md** ship in the package.

### Changed
- `package.json` carries `repository` / `bugs` / `homepage` fields pointing at the public release repo, so OpenUPM submission can pick up everything it needs.
- README rewritten as a production landing page: install via UPM git URL, connection flow, full configuration reference, troubleshooting.

### Fixed
- Stale config defence: legacy installs with `offlineMode = true` saved but no "has-ever-connected" flag are auto-corrected back to `offlineMode = false` on first window open, so visible state matches what the toggle would now allow.

---

## [2.0.2] — 2026-05-30

### Added
- Initial DLL-only distribution shape. Compiled `Argus.Runtime.dll` + `Argus.Editor.dll` + Claude integration files + manifests.

### Notes
- Previous internal versions shipped as source. v2.0.2 is the first compiled-only release.

---

## [Pre-2.0]

Internal development — not publicly distributed. See the dashboard's [Architecture overview](https://argus-profiler.com/docs/architecture) for the feature timeline.
