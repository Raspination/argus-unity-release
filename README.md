# Argus Profiler · `com.argus.profiler`

Production performance profiling for Unity games. Captures per-frame data + code-region attribution + device context from your build, uploads to the [Argus dashboard](https://argus-profiler.com) for visualisation, regression alerts, and AI-assisted optimisation reports.

> **About this repo** — DLL distribution only. The Unity package source lives in the operator's private workspace; this repo only carries the compiled assemblies + UPM manifest each release tag points at. See [SECURITY.md](SECURITY.md) for the rationale.

---

## Install

### Via Unity Package Manager (recommended)

1. **Window → Package Manager → + → Add package from git URL**
2. Paste:
   ```
   https://github.com/Raspination/argus-unity-release.git
   ```
   For repeatable team builds, pin a version:
   ```
   https://github.com/Raspination/argus-unity-release.git#v2.0.3
   ```
3. Install the peer dependency **UniTask** (the Editor assembly needs it):
   - **OpenUPM:** `openupm add com.cysharp.unitask`, OR
   - **Git URL:** `Window → Package Manager → + → Add from git URL` →
     ```
     https://github.com/Cysharp/UniTask.git?path=src/UniTask/Assets/Plugins/UniTask
     ```
4. Reload Unity. The **Tools → Argus Control** menu entry appears.

### Via `Packages/manifest.json` (no UI)

```jsonc
{
  "dependencies": {
    "com.argus.profiler": "https://github.com/Raspination/argus-unity-release.git#v2.0.3",
    "com.cysharp.unitask": "https://github.com/Cysharp/UniTask.git?path=src/UniTask/Assets/Plugins/UniTask",
    "com.unity.editorcoroutines": "1.0.0"
  }
}
```

Unity supports `2021.3 LTS` and newer.

---

## Connect to the dashboard

1. **Sign up** at <https://argus-profiler.com/signup>. A personal organisation is created automatically.
2. **Create a project** from the dashboard and open its **API keys** tab.
3. **Issue a new key** with the `sessions:write` permission. The cleartext value is shown **once** — copy it now (format `argus_` + 32 hex chars).
4. In Unity: **Tools → Argus Control** → paste the key → click **Connect**. The status pill flips to **● CONNECTED** when the dashboard accepts it.

Until you successfully connect at least once, the **Offline** toggle in the Connection card is disabled by design — there's no dashboard to be offline from yet. After the first connect, ticking Offline pauses uploads (captures still write to local JSON) for plane / travel work.

---

## Capture an event

Three patterns, ordered by frequency you'll actually use them. All are no-ops in `DISABLE_CHEATS` release builds and on platforms Argus doesn't support.

### Per-instance captures (the common case)

One capture per `(eventName, uniqueId)` pair per playtest run. Same `uniqueId` twice in the same run is silently dropped — keeps your dashboard from drowning in 12 identical "Order.Complete" rows when the player completes 12 sandwich orders.

```csharp
using Argus;

// Player completed an order — one perf snapshot per distinct order kind.
Argus.TriggerProfilerEvent("Order.Complete",
    duration: 3,
    uniqueId: orderConfig.DisplayName); // e.g. "Sandwich Order"

// Player started a chapter — one snapshot per chapter id.
Argus.TriggerProfilerEvent("Chapter.Start", 4,
    uniqueId: chapter.DisplayName);
```

### Per-kind captures (one shot per playtest)

Omit `uniqueId` when one capture per event KIND is enough — boot, scene load, things that happen at most once per playtest anyway.

```csharp
Argus.TriggerProfilerEvent("Boot.Start", 6);
Argus.TriggerProfilerEvent($"Scene.Load.{sceneId}", 4);
```

### Bypass dedup (regression hunting)

When you want every fire to capture (A/B'ing two runs of the same code path, before/after profiling of a fix), pass `repeatable: true`. The 30s cooldown still applies as a fail-safe — bump or drop it via [`repeatableEventCooldownSeconds`](#configuration).

```csharp
Argus.TriggerProfilerEvent("BossFight.Frame", 3, repeatable: true);
```

### Wrap hot code paths so spikes get a label

```csharp
using Argus;

void Update() {
    Argus.BeginRegion("EnemyAI.Tick");
    foreach (var enemy in _enemies) enemy.Tick();
    Argus.EndRegion();
}

// Or as a using-block — auto-ends even on exception:
void Tick() {
    using var _ = Argus.Region("Pathfinding");
    DoExpensiveSearch();
}
```

Spikes during the region carry the **region chain** (e.g. `Battle > EnemyAI > Pathfinding`), the active scene, and the dominant subsystem to the dashboard. The dashboard's "Top region timings" card surfaces total ms + call count + avg + max per region, turning the region API into a lightweight always-on profiler.

---

## Configuration

Create the config asset via **Assets → Create → Argus → Configuration**, then place it in any `Resources/` folder. The asset name must be exactly `ArgusConfig` — that's how the runtime finds it via `Resources.Load<ArgusConfig>("ArgusConfig")`.

| Field | Default | Description |
|---|---|---|
| `uploadCooldown` | `5` s | Minimum gap between batched HTTP uploads. Larger = fewer requests, smaller wire footprint per upload. |
| `maxPendingSessions` | `20` | Force-flush threshold. When the in-memory queue reaches this many sessions, upload immediately regardless of cooldown. |
| `compressUploads` | `true` | gzip the request body. 5–10× wire-size reduction on typical payloads; safe to leave on. |
| `offlineMode` | `false` | Skip dashboard uploads; captures still write to local JSON. Hidden in the Argus Control window until you've successfully connected at least once. |
| `alwaysSaveLocally` | `true` | Always write a local JSON backup alongside dashboard uploads. Useful for offline post-mortem with `argus:latest` / `argus:verify` Claude skills. |
| `maxFrameBuffer` | `300` | Frames retained per capture (~5 s at 60 fps). Higher = more context per spike but larger payload. |
| `captureFrameDebugger` | `true` | Auto-enable Unity's Frame Debugger during a capture (Editor-only). Adds per-draw-call data the dashboard can render. |
| `repeatableEventCooldownSeconds` | `30` | Per-name cooldown for `repeatable: true` events. Stops rapid-fire spam captures of the same name from flooding the dashboard. |
| `webglMode` | `Auto` | WebGL transport strategy. `Auto` tries the local Editor WebSocket bridge for 2s, falls back to direct HTTPS upload. `EditorBridge` requires the bridge. `DirectUpload` always uses HTTPS. |
| `webglProductionApiKey` | `""` | Production WebGL key baked into the build. Use a scope-restricted key (`sessions:write` only) — anything you put here is visible in the JS bundle. |

The Argus Control window's status pill reflects current state:

- **● CONNECTED** — key validated, uploads going through
- **● OFFLINE** — offline mode on (only available after first connect)
- **● ERROR** — last validation attempt failed; see the inline error message
- **○ NOT CONNECTED** — no key entered or never validated

---

## What ships in each capture

| Bucket | Fields |
|---|---|
| **Frame timing** | `frameTimes[]`, `frameTimesCPU[]`, `frameTimesGPU[]`, averages + percentiles |
| **Rendering** | `drawCalls[]`, `batches[]`, `triangles[]` per frame |
| **Subsystem ms** | per-frame `physicsMs`, `animationMs`, `uiMs`, `audioMs` |
| **GC** | `gcAllocPerFrameBytes[]` |
| **Spikes** | Top-10 list with `frameIndex`, `deltaMs`, `regionChain`, `scene`, `dominant`, per-thread + subsystem ms breakdown |
| **Region timings** | Per-region `callCount`, `totalMs`, `maxMs`, `avgMs` |
| **Asset memory** | `meshMemoryMB`, `textureMemoryMB` |
| **Scene context** | `activeScene`, all loaded scenes, counts of `Camera` / `Light` / `Renderer` / `ParticleSystem` / `AudioSource` / active GameObjects |
| **Run context** | git SHA (when available), scripting backend, build target, debug-build flag, quality preset + render scale + MSAA + shadow distance, display resolution + refresh rate + DPI, mobile thermal state + battery, network reachability |
| **Device fingerprint** | model, OS, GPU, RAM, app version, Unity version |

---

## Common workflows

### Trigger a one-off capture from the Editor

**Tools → Argus Control → Capture now** records a capture immediately for the test-session label currently entered in the window. Useful for "I just made a change, did it help?" comparisons without re-running the game.

### Disable in release builds

Argus's runtime API is `#if`-guarded out when `DISABLE_CHEATS` is in your Scripting Define Symbols (Player Settings → Other Settings → Scripting Define Symbols). All `Argus.TriggerProfilerEvent` / `Argus.BeginRegion` / `Argus.EndRegion` calls become no-ops — no overhead, no API surface, nothing in the build.

### Local-only captures for travel

After you've connected at least once, tick **Offline** in Argus Control. Captures land in your project's `ArgusCaptures/` folder as JSON instead of being uploaded. When you're back online, untick Offline; queued captures upload on the next interval.

### AI analysis with Claude

If you have Claude Code installed, the package's bundled `.claude-plugin/` registers three commands. Each operates on the most recent local capture (or the named one).

| Command | Purpose |
|---|---|
| `/argus:latest` | Summary + optimisation suggestions for the most recent capture |
| `/argus:verify` | Sanity-checks a capture: data quality, instrumentation gaps, suspicious values |
| `/argus:compare <a> <b>` | Diff two captures; flags quality-preset mismatch, scene-content changes, region-timing regressions |

---

## Troubleshooting

### "Argus Control not in the menu after install"

The package didn't compile. Check the Console for errors. The two most common causes:

- **Missing UniTask** — install via OpenUPM or git URL (see Install).
- **Scripting backend mismatch** — Argus needs .NET Standard 2.1+; if your project is on .NET Standard 2.0, raise it in Player Settings → Other Settings → API Compatibility Level.

### "Connect" button greyed out

The button enables when:
- A non-empty API key is entered
- The current state is not authenticated
- Offline mode is not on

If your key is correct and the button is still grey, the in-memory auth state thinks you're already connected. Click **Disconnect** to reset.

### Validation returns 403 / "key revoked"

The key was revoked from the dashboard, or rate limits are throttling validation. Re-issue a key in the project's API keys tab.

### Captures aren't showing on the dashboard

- The status pill in Argus Control must show **● CONNECTED** — if it shows **● OFFLINE**, captures only write to disk.
- Validation succeeds but uploads silently fail: check the Console for `[Argus]` log lines. Common causes are CORS misconfiguration on WebGL builds (set `INGEST_CORS_ORIGINS` for the host on the dashboard side) or rate-limit hits (per-key 600 requests / 15 min).
- Look in your project's `ArgusCaptures/` folder. If JSON files are there but the dashboard is empty, the connection path is broken.

### "Stale DLL" error in Releaser exports

Only relevant to the operator publishing new versions. Unity didn't rebuild the assemblies after a source change. Fix:

```
Tools → Argus → Recompile Scripts
```

then re-run **Tools → Argus → Export Compiled Package**.

---

## Versioning + upgrades

This package follows semantic versioning. Patch bumps (`2.0.x → 2.0.y`) are non-breaking — bump the `#v...` tag in your `Packages/manifest.json` and Unity refreshes the import on next reload.

Browse tags at [github.com/Raspination/argus-unity-release/tags](https://github.com/Raspination/argus-unity-release/tags). Release notes are in [`CHANGELOG.md`](CHANGELOG.md).

---

## Links

| | |
|---|---|
| Dashboard | <https://argus-profiler.com> |
| Quickstart docs | <https://argus-profiler.com/docs/quickstart> |
| Unity package docs | <https://argus-profiler.com/docs/unity> |
| Webhooks docs | <https://argus-profiler.com/docs/webhooks> |
| Account / API keys | <https://argus-profiler.com/docs/account> |
| Issue tracker | <https://github.com/Raspination/argus-unity-release/issues> |
| Support email | <support@argus-profiler.com> |
| Accessibility | <https://argus-profiler.com/legal/accessibility> |

---

## License

See [LICENSE.txt](LICENSE.txt). All rights reserved. Commercial use of the dashboard service is governed by the [Terms of Service](https://argus-profiler.com/legal/terms). Redistribution of the compiled assemblies in this repository requires written permission.
