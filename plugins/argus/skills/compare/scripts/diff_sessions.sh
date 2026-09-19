#!/usr/bin/env bash
# Diffs two Argus _claude.json events across the metrics that actually move.
# Highlights regressions ≥10% so the user can attribute them to a code change.
#
# Naming: each file IS one event (one Argus.TriggerProfilerEvent call). The
# user typically diffs events of the same eventName captured in two sessions
# — "before" and "after" a code change. The "session" concept (umbrella
# rollup of events) lives one level up; this script doesn't care about it.
#
# Phase Q additions (over the original perf-metric diff):
#   • Quality-preset mismatch flagged BLOCKING at the very top — apples-vs-
#     oranges baseline warning
#   • Scene-content delta (cameras, lights, renderers, particle systems) —
#     "you have 200 lights now, had 50" type findings
#   • Region timing delta — regressions, improvements, and new/removed
#     regions; the strongest "what changed in code" signal available
#     without git-diffing the source
#
# Usage: diff_sessions.sh <baseline.json> <candidate.json>

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)." >&2
  exit 1
fi

a="${1:-}"; b="${2:-}"
if [ -z "$a" ] || [ -z "$b" ] || [ ! -f "$a" ] || [ ! -f "$b" ]; then
  echo "ERROR: pass two existing _claude.json paths (baseline first)" >&2
  exit 1
fi

extract() {
  jq -r '
    {
      event:        .session.eventName,
      eventUniqueId: (.session.eventUniqueId // null),
      capturedAt:   .session.capturedAt,
      avgFPS:       (.frameStats.avgFPS // 0),
      avgMS:        (.frameStats.avgMS  // 0),
      p95MS:        (.frameStats.p95MS  // 0),
      maxGC_kB:     ([.memory.gcAllocationsPerFrame_KB // [] | max] | first // 0),
      monoUsedMB:   (.memory.monoUsedMB // 0),
      monoHeapMB:   (.memory.monoHeapMB // 0),
      meshMemoryMB:    (.memory.meshMemoryMB    // 0),
      textureMemoryMB: (.memory.textureMemoryMB // 0),
      drawCalls:    (.gpu.drawCalls // 0),
      batches:      (.gpu.batches   // 0),
      qualityLevel: (.runContext.quality.levelName  // null),
      renderScale:  (.runContext.quality.renderScale // null),
      msaa:         (.runContext.quality.msaa        // null),
      vSyncCount:   (.runContext.quality.vSyncCount  // null),
      isDebugBuild: (.runContext.build.isDebugBuild  // null),
      gitSha:       (.runContext.build.gitSha        // null),
      activeScene:        (.sceneContext.activeScene        // null),
      cameraCount:        (.sceneContext.cameraCount        // 0),
      lightCount:         (.sceneContext.lightCount         // 0),
      rendererCount:      (.sceneContext.rendererCount      // 0),
      particleSystemCount:(.sceneContext.particleSystemCount// 0),
      audioSourceCount:   (.sceneContext.audioSourceCount   // 0),
      regionTimings:      (.regionTimings // [])
    } | @json
  ' "$1"
}

ja=$(extract "$a")
jb=$(extract "$b")

# ── Quality-preset mismatch (BLOCKING — lead the report with this) ────────
# If any of the four quality-preset axes differ between baseline and
# candidate, prepend a warning so the user doesn't draw the wrong conclusion
# from a non-apples-to-apples comparison. The metrics that follow are still
# printed; the warning just frames them correctly.
jq -nr --argjson a "$ja" --argjson b "$jb" '
  def warn_if_diff(tag; av; bv):
    if av == bv then null else "  ⚠ \(tag): baseline=\(av // "(absent)") candidate=\(bv // "(absent)")" end;

  ( [warn_if_diff("quality.levelName"; $a.qualityLevel; $b.qualityLevel)]
  + [warn_if_diff("quality.renderScale"; $a.renderScale; $b.renderScale)]
  + [warn_if_diff("quality.msaa"; $a.msaa; $b.msaa)]
  + [warn_if_diff("quality.vSyncCount"; $a.vSyncCount; $b.vSyncCount)]
  + [warn_if_diff("build.isDebugBuild"; $a.isDebugBuild; $b.isDebugBuild)]
  ) | map(select(. != null)) as $warns |
  if ($warns | length) > 0 then
    ["⚠⚠⚠  COMPARISON IS NOT APPLES-TO-APPLES  ⚠⚠⚠",
     "Build / quality settings differ between the two events:"] + $warns
    + ["The metrics below may reflect those settings rather than code changes.", ""]
    | join("\n")
  else empty end
'

# ── Main perf-metric side-by-side ─────────────────────────────────────────
jq -nr --argjson a "$ja" --argjson b "$jb" '
  def round2: . * 100 | floor / 100;
  def deltaPct(av; bv):
    if av == 0 then (if bv == 0 then 0 else 9999 end) else ((bv - av) / av * 100) end;
  def fmt(v): (v | round2 | tostring);
  def warn(av; bv; metric_kind):
    (deltaPct(av; bv)) as $d |
    if (metric_kind == "lower_is_better" and $d >= 10) or
       (metric_kind == "higher_is_better" and $d <= -10)
    then "  ⚠ regression"
    else ""
    end;

  "─── Compare ───",
  "  baseline:  \($a.event)\(if $a.eventUniqueId then "  ·  \($a.eventUniqueId)" else "" end)   \($a.capturedAt)\(if $a.gitSha then "  ·  sha=\($a.gitSha | tostring | .[0:8])" else "" end)",
  "  candidate: \($b.event)\(if $b.eventUniqueId then "  ·  \($b.eventUniqueId)" else "" end)   \($b.capturedAt)\(if $b.gitSha then "  ·  sha=\($b.gitSha | tostring | .[0:8])" else "" end)",
  "",
  "  metric             baseline   candidate   Δ%      flag",
  "  avgFPS             \(fmt($a.avgFPS))      \(fmt($b.avgFPS))      \(deltaPct($a.avgFPS; $b.avgFPS) | round2)\(warn($a.avgFPS; $b.avgFPS; "higher_is_better"))",
  "  avgMS              \(fmt($a.avgMS))      \(fmt($b.avgMS))      \(deltaPct($a.avgMS; $b.avgMS) | round2)\(warn($a.avgMS; $b.avgMS; "lower_is_better"))",
  "  p95MS              \(fmt($a.p95MS))      \(fmt($b.p95MS))      \(deltaPct($a.p95MS; $b.p95MS) | round2)\(warn($a.p95MS; $b.p95MS; "lower_is_better"))",
  "  maxGC_kB           \(fmt($a.maxGC_kB))      \(fmt($b.maxGC_kB))      \(deltaPct($a.maxGC_kB; $b.maxGC_kB) | round2)\(warn($a.maxGC_kB; $b.maxGC_kB; "lower_is_better"))",
  "  monoUsedMB         \(fmt($a.monoUsedMB))      \(fmt($b.monoUsedMB))      \(deltaPct($a.monoUsedMB; $b.monoUsedMB) | round2)\(warn($a.monoUsedMB; $b.monoUsedMB; "lower_is_better"))",
  "  meshMemoryMB       \(fmt($a.meshMemoryMB))      \(fmt($b.meshMemoryMB))      \(deltaPct($a.meshMemoryMB; $b.meshMemoryMB) | round2)\(warn($a.meshMemoryMB; $b.meshMemoryMB; "lower_is_better"))",
  "  textureMemoryMB    \(fmt($a.textureMemoryMB))      \(fmt($b.textureMemoryMB))      \(deltaPct($a.textureMemoryMB; $b.textureMemoryMB) | round2)\(warn($a.textureMemoryMB; $b.textureMemoryMB; "lower_is_better"))",
  "  drawCalls          \($a.drawCalls)            \($b.drawCalls)            \(deltaPct($a.drawCalls; $b.drawCalls) | round2)\(warn($a.drawCalls; $b.drawCalls; "lower_is_better"))",
  "  batches            \($a.batches)            \($b.batches)            \(deltaPct($a.batches; $b.batches) | round2)\(warn($a.batches; $b.batches; "lower_is_better"))"
'

# ── Scene-content delta (Phase O) ─────────────────────────────────────────
# Only printed when both captures have sceneContext. Often the FIRST place
# to look for "why did perf change" — a scene that grew 4× the lights is a
# bigger smoking gun than any code change.
echo ""
jq -nr --argjson a "$ja" --argjson b "$jb" '
  def round1: . * 10 | floor / 10;
  def deltaPct(av; bv):
    if av == 0 then (if bv == 0 then 0 else 9999 end) else ((bv - av) / av * 100) end;
  def fmtRow(tag; av; bv):
    (deltaPct(av; bv)) as $d |
    "  \(tag)  baseline=\(av)  candidate=\(bv)  Δ \(($d | round1) | tostring)%" +
    (if ($d | fabs) >= 25 and av != bv then "  ⚠ likely regression cause" else "" end);

  if ($a.activeScene == null and $b.activeScene == null) then
    "─── Scene context ───\n  (absent in both events — pre-Phase-O captures)"
  else
    "─── Scene context delta ───",
    "  activeScene:  baseline=\($a.activeScene // "(absent)")  candidate=\($b.activeScene // "(absent)")\(if $a.activeScene != $b.activeScene then "  ⚠ scene changed" else "" end)",
    fmtRow("cameraCount        "; $a.cameraCount;         $b.cameraCount),
    fmtRow("lightCount         "; $a.lightCount;          $b.lightCount),
    fmtRow("rendererCount      "; $a.rendererCount;       $b.rendererCount),
    fmtRow("particleSystemCount"; $a.particleSystemCount; $b.particleSystemCount),
    fmtRow("audioSourceCount   "; $a.audioSourceCount;    $b.audioSourceCount)
  end
'

# ── Region timing delta (Phase P.1) ───────────────────────────────────────
# For each region present in either capture, compute Δ totalMs + Δ callCount.
# Surface the top regressions (regions that got significantly slower) +
# improvements (got faster) + any NEW or REMOVED region names. This is the
# strongest "what changed in code" signal we have without git-diffing.
echo ""
echo "─── Region timing delta ───"
jq -nr --argjson a "$ja" --argjson b "$jb" '
  def round2: . * 100 | floor / 100;

  # Build { region -> {totalMs, callCount} } dicts from each array.
  ( ($a.regionTimings // []) | map({key: .region, value: {totalMs: .totalMs, callCount: .callCount}}) | from_entries ) as $aDict |
  ( ($b.regionTimings // []) | map({key: .region, value: {totalMs: .totalMs, callCount: .callCount}}) | from_entries ) as $bDict |
  ( ($aDict | keys) + ($bDict | keys) | unique ) as $allRegions |

  if ($allRegions | length) == 0 then
    "  (no regionTimings in either event — wrap hot paths with Argus.BeginRegion to enable region-level diffs)"
  else
    # Build a richer per-region record per kind (BOTH / NEW / REMOVED).
    [ $allRegions[] |
      . as $r |
      ($aDict[$r] // null) as $av |
      ($bDict[$r] // null) as $bv |
      if $av == null then
        { region: $r, kind: "NEW",
          candidateMs: ($bv.totalMs // 0), candidateCalls: ($bv.callCount // 0) }
      elif $bv == null then
        { region: $r, kind: "REMOVED",
          baselineMs: ($av.totalMs // 0), baselineCalls: ($av.callCount // 0) }
      else
        { region: $r, kind: "BOTH",
          deltaMs: (($bv.totalMs // 0) - ($av.totalMs // 0)),
          baselineMs: $av.totalMs, candidateMs: $bv.totalMs,
          baselineCalls: $av.callCount, candidateCalls: $bv.callCount }
      end
    ] as $regions |

    # Sub-section renderers — each returns a single multi-line string.
    ( [$regions[] | select(.kind == "BOTH" and .deltaMs > 1)] | sort_by(-.deltaMs) | .[0:5] ) as $regressions |
    ( [$regions[] | select(.kind == "BOTH" and .deltaMs < -1)] | sort_by(.deltaMs) | .[0:5] ) as $improvements |
    ( [$regions[] | select(.kind == "NEW")] | sort_by(-.candidateMs) | .[0:5] ) as $new_regions |
    ( [$regions[] | select(.kind == "REMOVED")] | sort_by(-.baselineMs) | .[0:5] ) as $removed_regions |

    "  Top regressions (got slower, ≥1 ms):",
    ( if ($regressions | length) == 0 then "    (none above 1 ms threshold)"
      else ($regressions | map("    \(.region)  \((.baselineMs) | round2) → \((.candidateMs) | round2) ms  (Δ +\((.deltaMs) | round2) ms, calls \((.baselineCalls)) → \((.candidateCalls)))") | join("\n"))
      end ),
    "",
    "  Top improvements (got faster, ≥1 ms):",
    ( if ($improvements | length) == 0 then "    (none below -1 ms threshold)"
      else ($improvements | map("    \(.region)  \((.baselineMs) | round2) → \((.candidateMs) | round2) ms  (Δ \((.deltaMs) | round2) ms, calls \((.baselineCalls)) → \((.candidateCalls)))") | join("\n"))
      end ),
    "",
    "  New regions (in candidate, absent in baseline):",
    ( if ($new_regions | length) == 0 then "    (none)"
      else ($new_regions | map("    \(.region)  \((.candidateMs) | round2) ms over \((.candidateCalls)) calls") | join("\n"))
      end ),
    "",
    "  Removed regions (in baseline, absent in candidate):",
    ( if ($removed_regions | length) == 0 then "    (none)"
      else ($removed_regions | map("    \(.region)  \((.baselineMs) | round2) ms over \((.baselineCalls)) calls") | join("\n"))
      end )
  end
'
