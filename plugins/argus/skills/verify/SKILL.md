---
name: verify
description: Sanity-check that Argus is capturing real device data with proper code attribution. Use when the user says "verify argus", "is argus working", "is this device data", "argus health check", "is profiling instrumented", or seems confused about whether captures are sound.
tools: Bash, Read
---

# Argus verify

Quick green/red checklist of whether Argus is actually capturing useful device
data — and whether the captures carry enough code attribution to act on.

## Naming convention (please always use these terms in your reports)

- **event** = ONE `Argus.TriggerProfilerEvent(...)` call = one ~3s capture =
  one `_ai.json` file. A playtest typically produces 5–50 of these.
- **session** = the LOGICAL test-run rollup of multiple events sharing the
  same `sessionName` + `sessionInstanceId`. Don't call individual `_ai.json`
  files "sessions" — they're events. The session is the umbrella label.

The skill checks the following, top to bottom:

1. **Captures exist** at all (the directory was created, files have been written).
2. **Build identity** — `appVersion` (Application.version), `sessionName`,
   `sessionInstanceId`, and `runContext.build.gitSha` are populated, so
   regressions can be tied to a specific commit + build flavor + test run.
3. **Device data quality** — is this a phone build or just editor noise.
4. **Code-region instrumentation** — `regionTimings[]` is non-empty AND/OR
   at least one spike fell inside an `Argus.BeginRegion(...)` block. Without
   regions, spikes have no human-readable label and "where to optimise" is
   guesswork. With `regionTimings`, you also get the proper hot-path
   inventory (regions ranked by cumulative ms, not just spike frames).
5. **Scene context sanity** — `sceneContext.activeScene` is set, and the
   per-subsystem counts (cameras, lights, renderers, particles) aren't
   obvious smells.
6. **Asset memory budget** — `memory.meshMemoryMB` + `memory.textureMemoryMB`
   are within plausible mobile budgets (~300 MB combined).
7. **Run-context coverage** — `runContext.quality.levelName` is captured
   (so cross-capture comparisons can flag apples-vs-oranges quality changes).
8. **Hang/native coverage** (Phase AC) — `anrs` is present (an empty array is
   GOOD — detection ran, no freeze; absent means hang detection is off or the
   capture predates the feature) and `nativeMetrics.sampleCount > 0`. If `anrs`
   has entries, surface the worst freeze in the verdict. If `nativeMetrics`
   shows a `serious`/`critical` `peakThermalState`, note that perf readings from
   this capture are throttling-influenced.

## Steps

1. Run `${CLAUDE_PLUGIN_ROOT}/skills/latest/scripts/find_captures_dir.sh`. If it errors, report "captures directory missing — Argus has never run successfully" and stop.

2. Check that captures exist:
   ```
   ls -1t "<DIR>"/*_ai.json | head -5
   ```
   Count them and grab the latest 3.

3. For each of the latest 3 captures, extract device fingerprint, build identity, scene + asset signals, and instrumentation stats with one jq call per file:
   ```
   jq -r '[
     .session.eventName,
     .session.sessionName,
     .session.sessionInstanceId,
     .device.model,
     .device.os,
     .device.ramMB,
     .device.targetFPS,
     .device.appVersion,
     (.runContext.build.gitSha // "(absent)"),
     (.runContext.quality.levelName // "(absent)"),
     (.runContext.build.isDebugBuild // false),
     (.sceneContext.activeScene // "(absent)"),
     (.sceneContext.cameraCount // 0),
     (.sceneContext.lightCount // 0),
     (.memory.meshMemoryMB // 0),
     (.memory.textureMemoryMB // 0),
     .frameStats.avgFPS,
     .gpu.drawCalls,
     (.frameStats.regionsObserved // [] | length),
     (.regionTimings // [] | length),
     (.frameStats.spikes // [] | length)
   ] | @tsv' <file>
   ```

4. Apply the `is_likely_editor` heuristic:
   - **EDITOR DATA** if `device.model` matches `MacBook|iMac|Mac Pro|Mac mini|Mac Studio|Windows|.*Desktop|.*PC|Linux` AND `ramMB > 8000`.
   - **DEVICE DATA** otherwise.

5. Print a checklist exactly in this shape:

   ```
   ─── Captures ───
   ✓/✗ captures directory:    <path>
   ✓/✗ N events on disk, latest at <timestamp>

   ─── Build identity (Part A — which build produced this?) ───
   ✓/✗ session.sessionName:      "<value>"   <interpretation>
   ✓/✗ session.sessionInstanceId: "<value>"   <interpretation>
   ✓/✗ device.appVersion:        "<value>"   <interpretation>
   ✓/✗ device.unityVersion:      "<value>"
   ✓/✗ runContext.build.gitSha:  "<8-char-prefix>"   <interpretation>
   ✓/✗ runContext.build.isDebugBuild: <bool>   <interpretation>

   ─── Device data quality (Part B — device-side sampling) ───
   ✓/✗ device.model:    "<value>"   <interpretation>
   ✓/✗ avgFPS:          <value>     <interpretation>
   ✓/✗ drawCalls:       <value>     <interpretation>
   ✓/✗ runContext.quality.levelName: "<value>"   <interpretation>

   ─── Code-region instrumentation (Part C — can we attribute spikes?) ───
   ✓/✗ regionTimings:   N regions   <interpretation — top 3 by totalMs>
   ✓/✗ regionsObserved: N regions in spikes
   ✓/✗ spikes captured: N spikes    <interpretation>

   ─── Scene context (Part D — environment sanity) ───
   ✓/✗ activeScene:     "<name>"
   ✓/✗ cameraCount:     <N>   <interpretation>
   ✓/✗ lightCount:      <N>   <interpretation>
   ✓/✗ rendererCount:   <N>

   ─── Asset memory (Part E — VRAM budget) ───
   ✓/✗ meshMemoryMB:    <N>
   ✓/✗ textureMemoryMB: <N>
   ✓/✗ combined:        <N> MB   <interpretation vs 300/600 MB thresholds>

   ─── Device ↔ Editor link (Part F — WiFi reliability) ───
   ?  This skill cannot probe the link from outside Unity.
      In the device log (adb logcat / Xcode console), look for:
        [Argus] 🔌 Editor handshake received
        [Argus] ⚠ No editor heartbeat for >10s — N events queued, waiting
      If you see the warning, the link is down (network / firewall / wrong subnet);
      fix the link before profiling. On the Editor side, ArgusCaptures/
      connections_*.log and argus-editor.log record connects, drops and rotation.

   ─── Verdict ───
   <one-line summary: e.g. "Argus is reporting EDITOR data, not DEVICE data.">
   <one-line action: e.g. "Verify the build is a Development Build that defines ARGUS_ENABLED,
                            confirm the device is streaming in Argus Control's Devices card,
                            then re-capture.">
   ```

   Interpretation table for the per-row markers:

   | Row | ✓ when | ✗ when | What ✗ means in the verdict |
   |---|---|---|---|
   | `sessionName` | non-null, non-empty, not literally `"(unlabeled)"` | null or `"Default Session"` or empty | The event has no human-meaningful session label. Auto-tagging should kick in (`{ProductName}_{Date}`); if it didn't, the Argus package is out of date — update it. |
   | `sessionInstanceId` | non-null, 12+ chars | null or `"(absent)"` | The Argus package is pre-Phase L/Q — update it so the per-session-run dedup works correctly. |
   | `appVersion` | non-null, non-empty, non-`"(no version)"` | null/empty/placeholder | Application.version isn't being captured. Either the Unity tool is pre-Phase L (update the package) or PlayerSettings has no Version set. |
   | `gitSha` | non-null, non-`"(absent)"`, non-`"unknown"` | null/absent/unknown | Build provenance not wired. Editor captures need `git` on `PATH` to bake the SHA; device builds need `Assets/Argus/Generated/BuildInfo.cs` generated at build time via `ArgusBuildHook`. Not blocking; just means regressions are harder to bisect. |
   | `isDebugBuild` | `false` for perf analysis | `true` | Debug builds run 10-30% slower than release — caveat all perf conclusions accordingly. |
   | `model` | not editor-pattern | matches editor pattern | Editor noise — see existing "Verify the build is a Development Build…" action. |
   | `avgFPS` | > 5 | ≤ 5 on a non-editor capture | Frame data missing or zero. Often a sign the recorder didn't initialise. |
   | `drawCalls` | > 0 on device | == 0 on device | Render thread not sampled — confirm the build defines `ARGUS_ENABLED` (Project Settings → Player → Scripting Define Symbols) or every Argus call site was compile-stripped. |
   | `quality.levelName` | non-null, non-`"(absent)"` | null/absent | RunContext not wired — Unity tool predates Phase P. Update the Argus package. |
   | `regionTimings` | ≥ 1 | == 0 | The codebase isn't using `Argus.BeginRegion`. No hot-path inventory. When the array is populated, mention the top 3 by `totalMs` in the verdict as the suggested investigation targets. |
   | `regionsObserved` | ≥ 1 when spikes exist | == 0 with spikes present | The spikes happened OUTSIDE any region (or the regions weren't instrumented). Suggest wrapping hot loops. |
   | `spikes` | any number is fine; 0 means a quiet capture | — | Just informational. |
   | `activeScene` | non-empty | null/empty/`"(absent)"` | SceneContext not wired — Unity tool predates Phase O. Update the Argus package. |
   | `cameraCount` | ≤ 4 in normal scenes | > 4 | Often a smell — multiple full cameras drive a separate render pass each. Verify they're necessary. |
   | `lightCount` | < 100 in normal scenes | ≥ 100 | High dynamic light counts kill mobile perf in Forward rendering. Mention as a likely culprit before blaming code. |
   | `meshMemoryMB+textureMemoryMB` | < 300 combined | 300–600 (warn) / >600 (error) | Asset memory bloat. Texture compression + mesh LODs are the typical fixes. |

6. If the latest 3 are split (some editor, some device), report it explicitly — that means the link came up midway through the session and the user should trust only the device-data ones.

7. **When `regionsObserved == 0` but spikes exist**, end with this exact action line:

   ```
   Spikes have no code attribution. Add markers to your hot paths:
       Argus.BeginRegion("EnemyAI.Tick");
       // ... hot loop ...
       Argus.EndRegion();
   The next capture will tag every spike with the active region name,
   visible both in this skill's report and on the dashboard's Top spikes panel.
   ```

8. **Event-duplication check.** Argus drops a repeat of the same `eventName` + subject within one run, where the subject is `eventUniqueId`, or `eventTag` when no uniqueId is set. A device's run is its app process; in the Editor a new session instance starts on a label change or End Session Now. Only `repeatable: true` events may legitimately repeat the same pair. Run this query against the latest 20 captures in the most recent session instance:

   ```bash
   ls -1t "<DIR>"/*_ai.json | head -20 \
     | xargs jq -r '[.session.eventName, (.session.eventUniqueId // "(none)"), (.session.eventTag // "(none)")] | @tsv' \
     | sort | uniq -c | sort -rn | head -5
   ```

   Interpretations:
   - **All counts == 1** → dedup working correctly. ✓
   - **A row with count >= 2** for the SAME (eventName, eventUniqueId, eventTag) row → either:
     - Caller is using `repeatable: true`
     - Captures span multiple session instances (the dedup resets per-instance — that's expected)
     - Argus Unity tool is out of date (pre-Phase Q, no dedup) — ✗ tell the user to update the package
   - **Same eventName with DIFFERENT eventUniqueIds** (e.g. `FTUE.StartSequence` × `"ChapterSelectionFTUE"` and × `"InventoryFTUE"`) → normal, distinct logical events. ✓
   - **Same eventName with DIFFERENT eventTags** (e.g. `Item.Merge` × `"Plant_L3"` and × `"Plant_L4"`) → normal, one capture per distinct tag. ✓

   Surface the verdict on its own line:

   ```
   ─── Event dedup ───
   ✓ All (eventName, eventUniqueId, eventTag) rows unique within latest session instance
   ```

   or

   ```
   ─── Event dedup ───
   ✗ Found N captures with same (eventName, eventUniqueId): "<event>" × "<uniqueId>"
     Likely: caller is using repeatable=true, OR Argus tool is out of date.
   ```

## Output style

This skill exists to short-circuit confusion. Prefer 30 lines of clear status
over a paragraph of analysis. Do not run other tools — get in, give the
verdict, get out.

**Language**: in the verdict + interpretations, say "event" for one
`_ai.json`, "session" for the `(sessionName, sessionInstanceId)` rollup.
Don't conflate them. The user just shipped a webhook restructure built on
exactly this distinction; reverting to old language muddies their head.

## Versioning

Phase-L checks (`sessionName`, `appVersion`, `regionsObserved`) require the
Argus Unity tool from May 2026. Phase-O checks (`sceneContext`,
`memory.meshMemoryMB`, `memory.textureMemoryMB`) require the post-Phase-O
build. Phase-P checks (`regionTimings`, `runContext.build.gitSha`,
`runContext.quality.levelName`) require the post-Phase-P build. Phase-Q
checks (rich per-spike subsystem breakdown, `sessionInstanceId` surfaced)
require the post-Phase-Q exporter shipped here.

Older `_ai.json` files lacking these fields render as `(absent)` in the
summarize_session.sh output — that's an out-of-date Argus install, NOT a
device problem. Verdict should say so plainly so the user updates the package
instead of debugging their build.
