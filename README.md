# Argus Profiler — `com.argus.profiler`

Unity performance profiling utility with **offline JSON captures**, dashboard upload, and **AI-ready exports** for Claude and other assistants.

This package ships as precompiled assemblies. Source is not included.

---

## Install

### Via Unity Package Manager — local file

1. Copy this folder anywhere outside your Unity project (e.g. `~/Packages/com.argus.profiler/`).
2. In your project open `Packages/manifest.json` and add:
```json
{
  "dependencies": {
    "com.argus.profiler": "file:../../Packages/com.argus.profiler"
  }
}
```
3. UniTask is a peer dependency for the Editor assembly. Install via OpenUPM:
```
openupm add com.cysharp.unitask
```
   Or add the [official manifest entry](https://github.com/Cysharp/UniTask#install-via-git-url) if you don't use OpenUPM.
4. Reload Unity. The **Tools > Argus Control** window appears.

### Via Git URL (recommended)

Open **Window → Package Manager → + → Add package from git URL** and paste:
```
https://github.com/Raspination/argus-unity-release.git
```

Pin to a specific version:
```
https://github.com/Raspination/argus-unity-release.git#v2.0.2
```

UniTask peer dependency: install via OpenUPM (`openupm add com.cysharp.unitask`) or its [official git-URL manifest entry](https://github.com/Cysharp/UniTask#install-via-git-url).

---

## Quick Start

### Trigger a profiling capture from game code
```csharp
using Argus;

// One capture per (eventName, uniqueId) pair per session-instance.
Argus.TriggerProfilerEvent("FTUE.StartSequence", 3,
    uniqueId: sequence.SequenceId);

// Omit uniqueId when one capture per event KIND is enough.
Argus.TriggerProfilerEvent("Boot.Start", 6);

// `tag:` bypasses dedup — every fire captures, tag labels the row.
Argus.TriggerProfilerEvent("Order.Complete", 3,
    tag: orderConfig.DisplayName);
```

### Wrap hot code paths so spikes get a label
```csharp
using Argus;

void Update() {
    Argus.BeginRegion("EnemyAI.Tick");
    foreach (var enemy in _enemies) enemy.Tick();
    Argus.EndRegion();
}
```

Spikes during the region carry the region name + scene + dominant subsystem to the dashboard. Stripped at compile time in `DISABLE_CHEATS` release builds.

### Authenticate

Open **Tools > Argus Control**, paste the API key your dashboard issues for the project, click **Validate**. Once authenticated, captures upload automatically.

---

## Configuration

Create a config asset via **Assets > Create > Argus > Configuration** and place it in any `Resources/` folder named `ArgusConfig`.

| Field | Default | Description |
|---|---|---|
| `uploadCooldown` | `5` s | Min time between batched uploads |
| `maxPendingSessions` | `20` | Force-upload threshold |
| `offlineMode` | `false` | Skip HTTP; write local JSON only |
| `alwaysSaveLocally` | `true` | Always write local JSON backup |
| `maxFrameBuffer` | `300` | Frames retained per capture (~5s @ 60fps) |
| `captureFrameDebugger` | `true` | Auto-enable Frame Debugger per capture (Editor-only) |
| `repeatableEventCooldownSeconds` | `30` | Per-name cooldown for `repeatable: true` events |

---

## What ships in each capture

- Per-frame frame times (total, main thread, render thread)
- Per-frame draw calls / batches / triangles
- Per-frame physics / animation / UI / audio costs
- Per-frame GC allocations
- Top-10 spike list with region chain + scene + dominant subsystem
- Mesh + texture memory totals
- Device fingerprint (model, OS, GPU, RAM)
- Build info (app version, Unity version, scripting backend, git SHA if available)
- Quality settings + render scale + refresh rate

---

## Support

- Dashboard: https://argus-profiler.com
- Issues: support@argus-profiler.com

---

## License

See `LICENSE.txt`. All rights reserved. Redistribution prohibited without a commercial license.
