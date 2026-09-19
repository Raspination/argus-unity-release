# Changelog

All notable changes to `com.argus-profiler.unity` are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0] — 2026-09-19

### Added
- **Multi-device profiling.** A **Devices** card lists every device streaming to the Editor; each device is its own test session, tagged with its model. Concurrent streaming is capped by plan (`N / cap streaming`, **Upgrade** at the cap), with **Pause** / **Activate** per device and live status per row (streaming / idle / link down).
- **Multi-Device Mode** (`ArgusConfig.multiDeviceMode`, also in Controller → Advanced): `RoundRobin` (default — Unity PlayerConnection, one device at a time, no lost captures) or `WebSocket` (all devices stream at once). Baked into device builds.
- **Auto-connect on Unity load** — keeps Argus listening for devices across recompiles, Play mode, and Editor restarts.
- **iOS connectivity.** **Scan Wi-Fi for devices** finds development players on the local network and pins them; **iOS / direct IP** connects a phone by IP. iOS development builds (including CI builds) get `NSLocalNetworkUsageDescription` and `NSBonjourServices` in `Info.plist`.
- **Collapsible Controller sections.** Headers collapse to one-line summaries; a **Sections ▾** menu (or right-click a header) shows/hides sections with **Expand all**, **Collapse all**, **Reset to automatic**. Sections open and close with connection and device state; manual choices persist until that state changes.
- **Durable logs** in `ArgusCaptures/`: `argus-editor.log` mirrors every `[Argus]` console line; `connections_<timestamp>.log` records connect/disconnect/rotation events for each run.
- Key validation logs the destination project and org.
- A one-time warning when Offline mode is skipping uploads.

### Changed
- **No package dependencies.** UniTask and Editor Coroutines are no longer required; the Editor assembly uses plain `System.Threading.Tasks`. Installing by Git URL is now a single step.
- **Everything lives in Argus Control** (**Tools → Argus Control**). The `Tools → Argus` items for `ARGUS_ENABLED` (Enable in current / all build targets, Disable), **Regenerate Config Defaults**, and **Native Trace** moved to the Controller's **Advanced** section.
- **API key field is locked** behind **Edit** → **Save** / **Cancel**; the key is no longer committed on every keystroke.
- The **AI Export** section's button is now **Copy Last Export**; the history list is **Recent captures**.
- **Uploads retry transient failures** (network error, 5xx, 408, 429) at 3/10/30/60/120 s instead of being dropped. An unreachable dashboard no longer signs you out: only HTTP 401/403 rejects the key, and validation retries every 15 s (up to 8 times).
- A device's session now lasts for its whole app process and closes within ~30 s of the app quitting; the idle timeout that closes a silent device's session is 10 minutes.

### Fixed
- Device captures without a tag never uploaded.
- Duplicate captures and duplicate ANR records when a device re-sent a payload; ANR timestamps lost precision.
- Handlers stacked after recompiles, logging and uploading tagged captures several times; a payload that failed to ingest was re-sent forever; very long event names overflowed the file-name limit.
- The first frame after resuming a backgrounded app was recorded as a multi-second freeze; region timings accumulated from app launch instead of the capture window; spikes were labelled `scripts` without a measured render thread; each capture's first frame included time from before it started.
- AI export: empty per-spike breakdown on device captures, and a UTF-8 BOM that strict JSON parsers rejected.
- Several phones connected by direct IP kept dropping working links; a briefly unreachable phone could be locked out of the rotation for the rest of the run.
- iOS archive and link failures in the MetricKit plugin.
- "MessageHandler not registered" console error on a fresh Editor start, and Controller GUI errors after a recompile.

## [2.1.0] — 2026-06-28

### Added
- **UniTask declared as a package dependency.** The Editor assembly has always required UniTask (`com.cysharp.unitask`); it is now listed under `package.json` `dependencies` instead of being left as an undocumented prerequisite.
- **`Tools → Argus → Enable in All Build Targets`** — sets `ARGUS_ENABLED` on Standalone / Android / iOS / WebGL / tvOS / VisionOS / WSA in one click, for projects that build multiple platforms.

### Fixed
- **AI export (`*_ai.json`, legacy `*_claude.json`) produced invalid JSON under non-US locales.** Every numeric field was formatted with the ambient thread culture, so on a device whose OS locale uses a decimal comma (de/fr/es/it/pt/ru, …) values serialized as e.g. `"ms":33,457` — which the strict `jq`-based skills reject, breaking the AI-analysis path. The exporter now pins `InvariantCulture` for the whole build.
- **WebGL/player builds aborted with a `UnityEditor.CoreModule` reference error.** The runtime `ArgusSettings.OfflineMode` persisted via `EditorPrefs` behind an `#if UNITY_EDITOR` guard — but the shipped `Argus.Runtime.dll` is editor-compiled (`UNITY_EDITOR` defined), so the EditorPrefs call was baked into the runtime DLL, and Unity forbids runtime assemblies from referencing `UnityEditor`. Moved offline-mode persistence into the Editor assembly (`ArgusEditorOfflinePersistence`); the runtime field is now a plain in-memory bool. `Argus.Runtime.dll` once again has **zero** UnityEditor references (verify: `strings Argus.Runtime.dll | grep -c UnityEditor` → `0`).
- **Silent opt-in failure.** When `ARGUS_ENABLED` wasn't defined, the `[Conditional]` gating stripped every API call — so a connected device showed as connected but captured nothing, with no indication why. Now the package surfaces this loudly: a one-click "Enable Argus for &lt;platform&gt; now?" prompt on first import (per-project), plus a once-per-session console warning until enabled. Reworked `ArgusEnabledDefine.cs`: dropped the buggy global-EditorPrefs "seen once" guard (it fired once per machine across all projects) and the silent single-target auto-add.

---

## [2.0.5] — 2026-06-04

### Breaking

- **Package id renamed `com.argus.profiler` → `com.argus-profiler.unity`.** Reverse-DNS now matches the operator's actual domain. Remove the old package and re-add under the new id.
- **`DISABLE_CHEATS` opt-out replaced with `ARGUS_ENABLED` opt-in.** The public API methods are now `[Conditional("ARGUS_ENABLED")]`, so call sites are compile-stripped when the define is absent — release builds carry zero overhead. The Editor target auto-defines `ARGUS_ENABLED` on first package load (`Editor/ArgusEnabledDefine.cs`); enable per-platform via the new **Tools → Argus → Enable in Current Build Target** menu or via Project Settings → Player → Scripting Define Symbols. Removing the symbol is the inverse.
- **Capture file suffix renamed `_claude.json` → `_ai.json`** for vendor-neutrality (the export works with any LLM agent — Claude, ChatGPT, Cursor, Cline, Aider, …). Class renamed `ArgusClaudeExporter` → `ArgusAIExporter`. The legacy `*_claude.json` glob is still matched by `GetRecentAIExports` for the v2.0.5 + v2.0.6 transition; it will be dropped in v2.0.7. The bundled `.claude-plugin/` + `skills/` folders (Claude Code slash-commands) stay — they're optional integration on top of the underlying neutral JSON.

### Added

- **OpenUPM submission readiness.** `package.json` now carries `repository` / `bugs` / `homepage` blocks pointing at the public release repo. README installs OpenUPM-first.
- **Code-generated `ArgusConfig` defaults.** Inspired by Unity Input System's "Generate C# Class" toggle. The `ArgusConfig` ScriptableObject stays as the authoring surface; on every save, an `AssetPostprocessor` regenerates `ArgusConfigDefaults.cs` with each field baked as a `const`/`static readonly`. The new runtime facade `ArgusSettings` reads from those baked constants — **no more `Resources.Load<ArgusConfig>` at runtime**, no Resources/ folder mandate, no first-access cost. The asset can live anywhere in the project. The one runtime-mutable knob (`OfflineMode`) persists via EditorPrefs in the Editor.
- **`Tools → Argus → Regenerate Config Defaults`** menu for manual re-bake.
- **`Tools → Argus → Enable/Disable in Current Build Target`** menus to manage the `ARGUS_ENABLED` define per-platform.
- **SECURITY.md + CHANGELOG.md** ship in the package (Phase U.2).

### Changed

- README is now OpenUPM-first; "what if compilation errors" defensive copy removed; screenshot section added for the Argus Control window + ArgusConfig Inspector + Dashboard session detail. Drop those into `images/` before publishing.

### Fixed

- Argus Control's Settings card is now read-only (since values are baked at edit time); "Open ArgusConfig asset" button uses `AssetDatabase.FindAssets` instead of a Resources path, so the asset can live anywhere.
- Self-healing publish: the Releaser's `EnsureGitRepo` now does `git fetch + reset --soft origin/main` so each Export → Publish cycle stays in sync with the remote even though Export wipes the `.git` directory.

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
