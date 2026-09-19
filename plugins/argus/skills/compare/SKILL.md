---
name: compare
description: Compare two Argus profiling captures to detect regressions. Use when the user says "compare profiling", "regression check", "before vs after", "diff argus sessions", or asks whether a code change made performance worse.
tools: Bash, Read
---

# Argus compare

Diff two profiling events to spot regressions.

## Naming convention (use these terms in your report)

- **event** = ONE `Argus.TriggerProfilerEvent(...)` call = one `_ai.json` file.
  When the user says "compare", they typically mean comparing two events of the
  same `eventName` captured in two test runs — a "before" event and an "after"
  event.
- **session** = the umbrella rollup of multiple events sharing the same
  `sessionName` + `sessionInstanceId`. This skill does NOT compare sessions
  to each other; it compares two specific events.

## Steps

1. Resolve the captures directory via `${CLAUDE_PLUGIN_ROOT}/skills/latest/scripts/find_captures_dir.sh`.

2. Resolve the two file arguments from $ARGUMENTS:
   - If two paths are given: use them directly.
   - If `latest previous` is given (or no args): pick the two newest `*_ai.json` by mtime.
   - If two event-name fragments are given: match the newest `*_ai.json` files whose names contain those fragments.

3. Run `${CLAUDE_PLUGIN_ROOT}/skills/compare/scripts/diff_sessions.sh <baseline> <candidate>`. The script prints four sections in order:
   - **Build / quality mismatch warning** (only when relevant) — `⚠ COMPARISON IS NOT APPLES-TO-APPLES`. Quality preset, render scale, MSAA, vSync, or debug-build differs between the two events. **If this warning fires, lead your verdict with it** — any metric delta below could be the preset, not a code change. Suggest the user re-capture both events with matching presets before drawing conclusions.
   - **Perf metric side-by-side** — FPS, ms, p95, GC, mono, asset memory, draw calls, batches. The script flags ≥10% regressions on lower-is-better metrics and ≥10% drops on higher-is-better ones.
   - **Scene context delta** — camera/light/renderer/particle/audio source counts. The script flags any ≥25% delta with `⚠ likely regression cause`. A scene that grew 4× lights is usually a bigger smoking gun than any code change.
   - **Region timing delta** — top 5 regressions (regions whose `totalMs` grew ≥1 ms), top 5 improvements, NEW regions (in candidate but not baseline), REMOVED regions (gone in candidate). **This is the strongest "what changed in code" signal short of git-diffing**: a region that 3×'d its `totalMs` is exactly where to look in source.
   - **Hang/ANR delta** (Phase AC) — compare `anrs | length` and worst `stallMs` between the two events. A build that went **0 → 3 hangs**, or whose worst stall grew from a jank to a multi-second hang, is a regression at least as serious as a frame-time delta — call it out explicitly.
   - **Peak-thermal escalation** — compare `nativeMetrics.peakThermalState`. If the candidate ran hotter (`fair → critical`), warn that its perf numbers are throttling-influenced and the comparison may understate the candidate's true (un-throttled) cost.

4. Read the output and answer the user's likely question:
   - **Quality mismatch warning fires** → lead with that, before touching any metric. The right next step is re-capture, not analysis.
   - **Hang count jumped** → that's the headline regression. "Build B introduced 3 hangs that weren't in A" outranks a 5% frame-time delta.
   - **Region timing delta surfaces a clear regression** → quote it as the headline finding ("`Battle.Pathfinding` went 110 → 340 ms — that's the regression"), then cross-reference with the per-spike `region`/`regionChain` from the candidate event to see if those frames also got attributed to the same region.
   - **Scene-content delta fires** before any code-attribution issue → the regression is likely environmental, not code. Suggest the user check the scene's lighting / renderer setup before profiling further.
   - **Only perf metrics regressed, nothing else** → the regression is probably in code paths that aren't instrumented. Suggest wrapping the candidate event's biggest spike regions with `Argus.BeginRegion(...)` and re-capturing.
   - **Nothing regressed** → say so plainly. Don't invent issues.

5. If both events show editor-fingerprint data (avgFPS < 5 on a Mac/PC device), prepend a warning that the comparison reflects editor noise, not real device performance — the user should re-capture on device before drawing conclusions.

6. If both events are `isDebugBuild=true`, note that release-build perf would be ~10–30% better but the comparison itself is still valid (both sides paying the same debug overhead).

## Output style

Always include the four-section script output. Add a one-paragraph verdict on top: regression / no change / improvement, with the single most-impactful finding called out. **Lead with the quality-mismatch warning if present** — it invalidates everything else.
