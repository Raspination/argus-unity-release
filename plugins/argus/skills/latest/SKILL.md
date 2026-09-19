---
name: latest
description: Analyze the latest Argus profiling capture for this Unity project. Use when the user asks "analyze latest profiling", "latest argus session", "what does the profiling show", or asks about FPS, frame time, GC, memory, draw calls, or which code regions are causing spikes in this Unity project.
tools: Bash, Read
---

# Argus latest event

Analyze the most recent profiling capture (one *event* — one `Argus.TriggerProfilerEvent(...)` call — that lives in one `_ai.json` file) from this project's Argus tool.

## Naming convention (use these terms in your report)

- **event** = ONE `Argus.TriggerProfilerEvent(...)` call = one `_ai.json` file.
- **session** = the logical test-run rollup of multiple events sharing the
  same `sessionName` + `sessionInstanceId`. The dashboard groups events
  into sessions via this pair; Slack `test_session.completed` webhook fires
  once per session, not per event.

Reports should say "this event was captured during session X", NOT "this
session was captured" — each `_ai.json` is one event.

## Field surface available to the analysis

The capture now carries (Phases L–Q):

- `session.sessionName` / `sessionInstanceId` — the test-session label + 12-char run ID. Mention `sessionName` in the headline; the instance ID matters only when comparing two events that share a name (use it to confirm they came from the same logical run).
- `session.eventUniqueId` / `eventTag` — dedup label + display tag (the tag is also the dedup key when no uniqueId is set). Surface `eventUniqueId` in the headline when set ("Order.Complete · Sandwich Order"); it disambiguates two events of the same `eventName`.
- `device.appVersion` — the build's `Application.version`. Mention it once in the headline; lets the user correlate regressions to a specific build.
- **`regionTimings[]`** — the proper hot-path inventory (every region the event touched during its ~3s window, ranked by `totalMs`). When non-empty, **the top 3 entries anchor the report**: they tell the user where time was actually spent across ALL frames, not just spike frames.
- `frameStats.spikes[]` — rich per-spike breakdown. Each spike carries `region` + `regionChain` + `scene` + `dominant` AND per-subsystem ms (`mainThreadMs`, `renderThreadMs`, `physicsMs`, `animationMs`, `uiMs`, `audioMs`, `gcBytesThisFrame`, `drawCallsThisFrame`). **Use the subsystem-ms split** to give exact diagnoses, not just "dominant: scripts".
- `frameStats.regionsObserved[]` — distinct regions seen across spikes (subset of `regionTimings` — only the spike-frame ones). Quick "is the codebase instrumented" sanity check.
- **`runContext.build.gitSha`** — commit SHA of the build. Cite the 8-char prefix when comparing to a baseline ("this is `abcdef12`, your baseline was `12345678`").
- **`runContext.build.isDebugBuild`** — when `true`, caveat ALL perf conclusions: release-build perf is typically 10–30% better. Mention this once in the headline if it's a debug build.
- **`runContext.quality.{levelName,renderScale,msaa,vSyncCount}`** — caveats every cross-event comparison. Different presets = not apples-to-apples; if the user invokes `/argus:latest` while a baseline is implied, check the preset matches.
- **`sceneContext.{activeScene,cameraCount,lightCount,...}`** — answers "why is this scene slow?". Mention the active scene + any anomalous count (>4 cameras, >100 lights) in the headline so the user investigates scene composition before blaming code.
- **`memory.{meshMemoryMB,textureMemoryMB}`** — asset bloat axis. Mention these when combined exceeds 300 MB ("texture memory at 215 MB — that's the top GPU VRAM consumer").
- **`perFrame.*_samples`** — downsampled per-frame arrays (drawCalls, batches, triangles, physicsMs, animationMs, uiMs, audioMs). For spotting per-frame patterns ("draw calls climbed steadily from 220 → 487 over the capture, suggesting per-frame instantiation"). The summary script prints min/median/max per axis as a starting hint.
- **`anrs[]`** — user-visible main-thread freezes (Phase AC). Each carries `severity` (jank/hang/anr), `stallMs`, `lastFrameIndex`, `regionChain`/`scene`, `source` (`watchdog` = this run; `android_exit_info`/`ios_metrickit` = OS ground-truth recovered from a prior run, flagged `recoveredFromPriorRun`). **A freeze is a headline finding** — lead with the worst one ("a 2.3s hang fired during `Battle > EnemyAI`"). Empty array = detection ran, no freeze (good — say so). Absent = feature off / old capture.
- **`nativeMetrics`** — thermal trend, native heap, available memory, memory pressure (Phase AC). **The key reframe**: if `peakThermalState` is `serious`/`critical`, a slow capture may be the device THROTTLING, not heavy code — say this explicitly before recommending code changes.

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/latest/scripts/find_captures_dir.sh` to resolve the project's `ArgusCaptures` directory. If it errors, surface the error and stop.

2. List `*_ai.json` files in that directory sorted by modification time (newest first):
   ```
   ls -1t "<DIR>"/*_ai.json | head -1
   ```

3. Run `${CLAUDE_PLUGIN_ROOT}/skills/latest/scripts/summarize_session.sh <path>` to extract structured stats. The script's output includes "Run context", "Scene context", "Top region timings", "Top frame-time spikes (with code attribution)" (with a per-subsystem sub-line beneath each spike when Phase-P data is present), and "Per-frame samples" sections — read all of them before composing the report.

4. **Sanity check first.** If `is_likely_editor` is `true` AND `avgFPS < 5` AND `drawCalls == 0`, prepend a clear warning:

   > ⚠ This event is editor data, not device data. Argus's device-side sampling path (`ArgusDeviceSampler`) may not have been reached — verify the build is a Development Build, the build target defines `ARGUS_ENABLED` (Project Settings → Player → Scripting Define Symbols), and the device is listed as streaming in the Devices card of Tools → Argus Control. Until that's resolved, every metric below describes the editor, not the phone.

   Without this warning the user may waste hours debugging "performance" that's actually editor idle.

5. **Run-context caveat (gate every perf conclusion through this).**
   - If `runContext.build.isDebugBuild == true`, mention once: "Debug build — release perf will be ~10–30% better; factor that into recommendations."
   - If a baseline event is implied (the user said "compared to last time" / "since I changed X"), check `runContext.quality.levelName` + `renderScale` + `msaa` against memory. If different, lead with: "⚠ Quality preset is `<X>` (was `<Y>`); not apples-to-apples — switch back to baseline preset before drawing conclusions."

6. Report findings in this order:

   - **Headline (1 line)** — `<sessionName> · <eventName>[ · <eventUniqueId>] on <device.model> in <activeScene> · v<appVersion>[ · DEBUG] · <capturedAt>`. Omit `appVersion`/`eventUniqueId` if `(no version)`/null. Mention `DEBUG` only when `isDebugBuild=true`.
   - **Hot path (anchor of the report)** — if `regionTimings[].length > 0`, lead with the top 3 by `totalMs`: *"Battle.Pathfinding (340 ms total over 48 calls, 7 ms avg, 87 ms max) — this is your single biggest cumulative cost this event."* This is the highest-signal finding because it covers EVERY frame, not just spike frames.
   - **Frame stats** — avgFPS, p95 ms, spike count.
   - **Top 3 frame-time spikes** — for each spike: `frame[N] <ms>ms` followed by attribution. Format depends on what's available:
     - **Rich Phase-P spike**: `frame[142] 87.3 ms — region chain "Battle > EnemyAI > Pathfinding" in scene "Battle_Boss". Subsystem split: 62.1ms main / 18.2ms physics / 7.0ms render / 100KB GC / 487 draws.` Quote the actual ms-split — it lets the user say "scripts dominated despite physics being high" with certainty.
     - **Phase-L spike, no subsystem breakdown**: `frame[84] 87.3ms — region "EnemyAI.Tick" in scene "Boss_Fight" (dominant: scripts)`
     - **Old capture, magnitude only**: `frame[84] 87.3ms — pre-Phase L capture, no attribution available`
   - **Scene context (when present)** — one line: *"Active scene `Battle_Boss` has 3 cameras, 187 lights, 412 renderers, 24 particle systems."* Flag a count >4 cameras or >100 lights with a "← investigate before blaming code" note.
   - **Asset memory (when present + above threshold)** — one line when `meshMemoryMB + textureMemoryMB > 300`: *"Asset memory 263 MB (mesh 48 + texture 215) — texture memory is the top VRAM consumer; check the Texture Importer for unused mips / oversized atlases."*
   - **Top 3 GC spikes** by frame index, with kB values (from the GC section of `summarize_session`).
   - **Memory** — monoUsedMB and totalReservedMB.
   - **GPU** — drawCalls, batches.
   - **Per-frame patterns (when relevant)** — only mention if a sampled axis shows a striking shape, e.g. `drawCalls: 220 / 280 / 487` → "draw calls climbed steadily over the event, suggesting per-frame instantiation rather than a one-off spike". Skip when the min/median/max are flat.
   - **Optimisation opportunities** — see step 7.

7. **Optimisation triage.** Use regionTimings + per-spike subsystem split to point at concrete files, not vague advice:

   - **If `regionTimings` is populated**, the top-N regions ARE the hot paths. Quote the leader directly: *"Battle.Pathfinding accounts for 340 ms cumulative (87 ms worst single call). Inspect that function first — it's both spiky AND consistently expensive."* This is the strongest finding because it covers the whole event, not just spike frames.
   - **If a spike has a non-zero per-subsystem breakdown**, quote the split before naming a culprit: *"The 87 ms spike at frame 142 split as 62 ms main / 18 ms physics — it's script-bound, not physics-bound despite physics being above its usual baseline."* The 8-bucket `dominant` field is a hint; the breakdown is the truth.
   - **If a region appears repeatedly in spikes**, that's the regression smoking gun. E.g. *"3 of the top 5 spikes happened in `EnemyAI.Tick` (87 / 64 / 51 ms). The function is firing >2× expected — likely a regression in the last commits."*
   - **If no regions are present but `dominant` is consistent**, name the subsystem and the file pattern to look at:
     - `dominant: scripts` → "Most spikes are CPU-side game logic. Look at MonoBehaviour `Update`/`FixedUpdate` calls in the active scene (`<sceneContext.activeScene>`). Wrap suspect methods with `Argus.BeginRegion(\"<name>\")` and re-capture for line-level attribution."
     - `dominant: render` → "Most spikes are render-thread bound. Inspect draw call breakdown in Frame Debugger — typical causes: unbatched UI, shader recompiles, oversized shadow maps. With `sceneContext.cameraCount > 1`, also verify each camera's necessary (each one is a full render pass)."
     - `dominant: physics` → "Physics dominates. Check FixedUpdate cost + active rigidbody count (`<physics.activeRigidbodies>`); reduce physics tick rate if frame budget allows, or sleep/disable rigidbodies outside camera frustum."
     - `dominant: animation` → "Animator-bound. Check Animator update mode (Normal vs UnscaledTime), state machine complexity, or whether off-screen GameObjects could disable their Animator components."
     - `dominant: ui` → "UI-thread bound. Common culprits: large dirty canvases that re-batch every frame, deeply nested layout groups, expensive Text mesh rebuilds. Break the canvas into static + dynamic sub-canvases."
     - `dominant: audio` → "Audio mixing dominant — voice count or DSP load. Check `audio.playingVoices` (`<audio.playingVoices>`) and `audio.loadPercent` (`<audio.loadPercent>%`)."
     - `dominant: gc` → "Top spikes coincide with large GC allocations. Cross-reference the 'Top GC spikes' section above for the exact frames; common culprits: per-frame `string.Format`, `LINQ.Where`, `new List<>()`, allocating `foreach` over `Dictionary`."
   - **If neither regions nor dominant data exists** (older capture or all-quiet frames): note it once and fall back to generic advice tied to whichever metric is worst.

8. **If `regionTimings` is empty** (no `Argus.BeginRegion(...)` instrumentation), end with this nudge (one paragraph):

   > No `Argus.BeginRegion(...)` calls fired this event, so the report relies on spike attribution alone — it can point at scenes and subsystems, not specific functions. Wrapping the 3–5 hottest code paths in your project (e.g. AI tick, physics step, network update) will turn the next event's analysis into named-method findings AND give you the per-region cumulative timing table. Example:
   > ```csharp
   > Argus.BeginRegion("EnemyAI.Tick");
   > foreach (var enemy in enemies) enemy.Tick();
   > Argus.EndRegion();
   > ```

9. If `$ARGUMENTS` is provided (e.g. `gc`, `memory`, `frame-time`, `gpu`, `regions`, `scene`), focus the analysis on that area and skip unrelated sections. `regions` shows the top region timings; `scene` summarises `sceneContext` + suggests scene-level fixes.

## Output style

Tight, factual, optimisation-oriented. Prefer specific numbers and named regions ("3 spikes in `EnemyAI.Tick`, all >50 ms") over generic prose ("there are some spikes"). Do not pad with disclaimers — flag the editor-data warning + the quality-preset caveat if relevant, then move on. The whole report should fit in roughly 30–50 lines on a wide terminal.

**Language**: use "event" for the per-`_ai.json` analysis, "session" for the rollup. The user just shipped a webhook restructure built on this distinction — reverting to old language muddies their head.
