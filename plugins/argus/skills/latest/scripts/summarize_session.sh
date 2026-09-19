#!/usr/bin/env bash
# Pretty-prints structural stats for a single Argus _claude.json session.
# Designed for Claude to consume directly — plain text, no JSON wrapping.
#
# Usage: summarize_session.sh <path-to-_claude.json>
#
# Naming convention used throughout:
#   • event   = ONE Argus.TriggerProfilerEvent call (one ~3s capture, one row)
#               One _claude.json file = one event.
#   • session = the logical test-run rollup of multiple events sharing the
#               same sessionName + sessionInstanceId.
#
# Knows about all field surfaces shipped through Phase Q:
#   Phase L  → session.eventUniqueId, device.appVersion, spikes carry
#              region/scene/dominant, frameStats.regionsObserved
#   Phase M  → session.eventTag + per-(eventName,uniqueId)-per-session dedup
#   Phase O  → memory.{meshMemoryMB,textureMemoryMB}, perFrame.*_samples,
#              sceneContext (active scene + per-subsystem counts)
#   Phase P  → spikes carry regionChain + per-subsystem ms breakdown
#              (mainThreadMs, physicsMs, etc.), regionTimings[], runContext
#              (build/quality/display/mobile/network)
#   Phase Q  → this script reads everything above; older _claude.json files
#              missing a field render as "—" / "(absent)" so nothing crashes.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required (brew install jq)." >&2
  exit 1
fi

file="${1:-}"
if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "ERROR: pass a path to a _claude.json file" >&2
  exit 1
fi

# Header / Device / Frame stats / Memory / GPU — single jq pass.
jq -r '
  def is_likely_editor(model; ram):
    (model | test("MacBook|iMac|Mac Pro|Mac mini|Mac Studio|Windows|.*Desktop|.*PC|Linux"; "i")) and (ram > 8000);

  def round2: . * 100 | floor / 100;

  . as $s |
  ($s.session // {}) as $sess |
  ($s.device // {}) as $dev |
  ($s.frameStats // {}) as $fs |
  ($s.memory // {}) as $mem |
  ($s.gpu // {}) as $gpu |

  "─── Header ───",
  "  event:        \($sess.eventName // "?")\(if ($sess.eventUniqueId // null) != null and ($sess.eventUniqueId | tostring) != "" then "  ·  uniqueId: \($sess.eventUniqueId)" else "" end)\(if ($sess.eventTag // null) != null and ($sess.eventTag | tostring) != "" then "  ·  tag: \($sess.eventTag)" else "" end)",
  "  sessionName:  \($sess.sessionName // "(unlabeled)")",
  "  sessionInstanceId: \($sess.sessionInstanceId // "(absent)")",
  "  environment:  \($sess.environment // "?")",
  "  capturedAt:   \($sess.capturedAt // "?")",
  "  duration:     \($sess.durationSeconds // 0)s   (\($sess.frameCount // 0) frames)",
  "",
  "─── Device ───",
  "  model:        \($dev.model // "?")",
  "  os:           \($dev.os // "?")",
  "  cpu:          \($dev.cpu // "?")",
  "  ramMB:        \($dev.ramMB // 0)",
  "  unityVersion: \($dev.unityVersion // "?")",
  "  appVersion:   \($dev.appVersion // "(no version)")",
  "  targetFPS:    \($dev.targetFPS // "?")",
  "  is_likely_editor: \(is_likely_editor($dev.model // ""; ($dev.ramMB // 0)))",
  "",
  "─── Frame stats ───",
  "  avgFPS:       \(($fs.avgFPS // 0) | round2)",
  "  avgMS:        \(($fs.avgMS // 0)  | round2)",
  "  p50/p95/p99:  \(($fs.p50MS // 0) | round2) / \(($fs.p95MS // 0) | round2) / \(($fs.p99MS // 0) | round2)",
  "  spikeCount:   \($fs.spikeCount // 0)",
  "",
  "─── Memory ───",
  "  monoUsedMB:   \(($mem.monoUsedMB // 0) | round2)",
  "  monoHeapMB:   \(($mem.monoHeapMB // 0) | round2)",
  "  totalReservedMB: \(($mem.totalReservedMB // 0) | round2)",
  "  meshMemoryMB:    \(($mem.meshMemoryMB // 0) | round2)",
  "  textureMemoryMB: \(($mem.textureMemoryMB // 0) | round2)",
  "",
  "─── GPU ───",
  "  drawCalls:    \($gpu.drawCalls // 0)",
  "  batches:      \($gpu.batches // 0)",
  "  triangles:    \($gpu.triangles // 0)",
  "  gpuVramUsedMB: \(($gpu.gpuVramUsedMB // 0) | round2)"
' "$file"

# ── Run context (Phase P.2) ──────────────────────────────────────────────
# Only printed when runContext is non-null (older captures lacking it skip
# this whole block silently). Each sub-section also short-circuits when its
# own subobject is null — desktop captures legitimately have null .mobile.
echo ""
jq -r '
  if (.runContext // null) == null then
    "─── Run context ───\n  (absent — pre-Phase-P capture)"
  else
    (.runContext // {}) as $rc |
    "─── Run context ───",
    ( if $rc.build != null then
        "  build:    sha=\($rc.build.gitSha // "?" | tostring | .[0:8])  ·  backend=\($rc.build.scriptingBackend // "?")  ·  target=\($rc.build.buildTarget // "?")  ·  debug=\($rc.build.isDebugBuild // false)"
      else "  build:    (absent)" end ),
    ( if $rc.quality != null then
        "  quality:  \($rc.quality.levelName // "?")  (MSAA \($rc.quality.msaa // 0), vSync \($rc.quality.vSyncCount // 0), renderScale \($rc.quality.renderScale // 1), pipeline \($rc.quality.renderPipelineName // "Built-in"))"
      else "  quality:  (absent)" end ),
    ( if $rc.display != null then
        "  display:  \($rc.display.width // 0)×\($rc.display.height // 0) @ \($rc.display.refreshRate // 0)Hz  ·  \($rc.display.dpi // 0) dpi  ·  \($rc.display.orientation // "?")"
      else "  display:  (absent)" end ),
    ( if $rc.mobile != null and (($rc.mobile.thermalState // "") != "" or ($rc.mobile.batteryLevel // 0) > 0) then
        "  mobile:   battery=\($rc.mobile.batteryLevel // 0) (\($rc.mobile.batteryStatus // "?"))  ·  thermal=\($rc.mobile.thermalState // "?")"
      else empty end ),
    ( if $rc.network != null then
        "  network:  start=\($rc.network.reachabilityAtStart // "?")  ·  end=\($rc.network.reachabilityAtEnd // "?")\(if ($rc.network.changedDuringCapture // false) then "  ⚠ CHANGED during capture" else "" end)"
      else empty end )
  end
' "$file"

# ── Scene context (Phase O) ──────────────────────────────────────────────
echo ""
jq -r '
  if (.sceneContext // null) == null then
    "─── Scene context ───\n  (absent — pre-Phase-O capture)"
  else
    (.sceneContext // {}) as $sc |
    "─── Scene context ───",
    "  active:   \($sc.activeScene // "?")  (\($sc.cameraCount // 0) cam · \($sc.lightCount // 0) light · \($sc.rendererCount // 0) renderer · \($sc.particleSystemCount // 0) particle · \($sc.audioSourceCount // 0) audio · \($sc.activeGameObjectCount // 0) active GOs)",
    ( if (($sc.loadedScenes // []) | length) > 1 then
        "  loaded:   \($sc.loadedScenes | join(", "))"
      else empty end )
  end
' "$file"

# ── Top region timings (Phase P.1) ───────────────────────────────────────
# The proper hot-path inventory. Every region the session touched, sorted by
# totalMs descending (exporter handles the sort). When empty: the session
# ran no Argus.BeginRegion calls and perf attribution will be coarse.
echo ""
echo "─── Top region timings ───"
jq -r '
  (.regionTimings // []) as $rt |
  if ($rt | length) == 0 then
    "  (no Argus.BeginRegion(\"Name\") instrumentation in this session — perf attribution stays coarse; spike attribution is the only signal)"
  else
    ( [
        "  region                                              calls    total ms    avg ms    max ms",
        "  ─────────────────────────────────────────────────  ──────  ──────────  ────────  ────────"
      ] +
      ( $rt | .[0:10] | map(
          "  " + ((.region // "?") | .[0:48] | . + (" " * (48 - length)))
              + "  " + ((.callCount // 0) | tostring | . + (" " * (6 - length)))
              + "  " + ((.totalMs // 0) | . * 100 | floor / 100 | tostring | . + (" " * (10 - length)))
              + "  " + ((.avgMs // 0) | . * 100 | floor / 100 | tostring | . + (" " * (8 - length)))
              + "  " + ((.maxMs // 0) | . * 100 | floor / 100 | tostring)
        )
      )
    ) | join("\n")
  end
' "$file"

# ── Top GC spikes (kB) ───────────────────────────────────────────────────
echo ""
echo "─── Top GC spikes (kB) ───"
jq -r '
  ([.memory.gcAllocationsPerFrame_KB // [] | to_entries | sort_by(-.value) | .[0:5][] | "  frame[\(.key)]: \(.value | . * 100 | floor / 100) kB"] | join("\n"))
' "$file"

# ── Top frame-time spikes (Phase L + Phase P sub-line) ───────────────────
# Each spike: headline row + a sub-line breakdown when Phase-P fields are
# present (non-zero). Pre-Phase-P captures (subsystem ms all-zero) print
# only the headline. Pre-Phase-L captures (bare numbers, not objects) get
# the magnitude-only fallback.
echo ""
echo "─── Top frame-time spikes (with code attribution) ───"
jq -r '
  ([.frameStats.spikes // []
    | .[0:10][]
    | (
        if type == "object" then
          # Headline line — region chain preferred over plain region when
          # available, so nested instrumentation reads top-down.
          "  frame[\(.frameIndex)] \(.ms | . * 100 | floor / 100) ms" +
          "  region=\((.regionChain // .region) // "—")" +
          "  scene=\(.scene // "—")" +
          "  dominant=\(.dominant // "—")"
          +
          # Sub-line: per-subsystem ms breakdown. Only print if ANY
          # subsystem-ms field is non-zero (Phase-P presence check); pre-
          # Phase-P captures default all subsystem-ms to 0 in the exporter
          # so the all-zero check is the right gate.
          ( if ((.mainThreadMs // 0) + (.renderThreadMs // 0) + (.physicsMs // 0) + (.animationMs // 0) + (.uiMs // 0) + (.audioMs // 0)) > 0 then
              "\n     └ cpu=\(.mainThreadMs // 0 | . * 100 | floor / 100)ms · gpu=\(.renderThreadMs // 0 | . * 100 | floor / 100)ms · phys=\(.physicsMs // 0 | . * 100 | floor / 100)ms · anim=\(.animationMs // 0 | . * 100 | floor / 100)ms · ui=\(.uiMs // 0 | . * 100 | floor / 100)ms · audio=\(.audioMs // 0 | . * 100 | floor / 100)ms · gc=\(((.gcBytesThisFrame // 0) / 1024) | . * 10 | floor / 10)KB · draws=\(.drawCallsThisFrame // 0)"
            else "" end )
        else
          "  spike \(. | . * 100 | floor / 100) ms  (legacy capture — no attribution)"
        end
      )]
   | if length == 0 then "  (no spikes detected — frame times stayed within 2× rolling avg)" else join("\n") end)
' "$file"

# ── Per-frame samples (Phase O/P; downsampled) ───────────────────────────
# Cheap summary of the new per-frame arrays so Claude knows they're
# present and where to fish for per-frame patterns when needed. Format is
# min / median / max across the sampled series — gives the shape without
# dumping ~100 numbers per axis into the report.
echo ""
echo "─── Per-frame samples (min / median / max across N samples) ───"
jq -r '
  (.perFrame // null) as $pf |
  if $pf == null then
    "  (absent — pre-Phase-O capture; full arrays live on .perFrame.*_samples once present)"
  else
    def stats: if length == 0 then "—" else
      (sort) as $sorted |
      "\($sorted[0] | . * 10 | floor / 10) / \($sorted[length / 2 | floor] | . * 10 | floor / 10) / \($sorted[-1] | . * 10 | floor / 10)"
    end;
    [
      "  drawCalls:    \(($pf.drawCalls_samples // []) | stats)",
      "  batches:      \(($pf.batches_samples // []) | stats)",
      "  triangles:    \(($pf.triangles_samples // []) | stats)",
      "  physicsMs:    \(($pf.physicsMs_samples // []) | stats)",
      "  animationMs:  \(($pf.animationMs_samples // []) | stats)",
      "  uiMs:         \(($pf.uiMs_samples // []) | stats)",
      "  audioMs:      \(($pf.audioMs_samples // []) | stats)",
      "  (\($pf.sampleCount // 0) samples per axis — full arrays under .perFrame.*_samples)"
    ] | join("\n")
  end
' "$file"

# ── Hangs & ANRs (Phase AC) ──────────────────────────────────────────────
echo ""
echo "─── Hangs & ANRs ───"
jq -r '
  (.anrs // null) as $a |
  if $a == null then
    "  (absent — hang detection off or pre-Phase-AC capture)"
  elif ($a | length) == 0 then
    "  none — hang detection ran, no user-visible freeze recorded ✓"
  else
    ($a | sort_by(-.stallMs)) as $sorted |
    ([ "  \($a | length) freeze(s) recorded:" ] +
     ($sorted | .[0:5] | map(
       "    \(.severity // "?") · \((.stallMs // 0) | floor)ms · frame \(.lastFrameIndex // -1)"
       + " · \(.regionChain // .region // .scene // "—")"
       + " · src=\(.source // "?")"
       + (if .recoveredFromPriorRun then " (prior run)" else "" end)
     ))) | join("\n")
  end
' "$file"

# ── Native metrics (Phase AC) ────────────────────────────────────────────
echo ""
echo "─── Native metrics ───"
jq -r '
  (.nativeMetrics // null) as $n |
  if $n == null then
    "  (absent — native metrics off or pre-Phase-AC capture)"
  else
    [
      "  thermal trend:  \((($n.thermalTrend // []) | join(" → ")) // "—")",
      "  peak thermal:   \($n.peakThermalState // "—")  ·  throttle: \($n.cpuThrottleHint // "—")",
      "  native heap:    \(((($n.nativeHeapBytes // -1) | if . < 0 then "—" else (. / 1048576 * 10 | floor / 10 | tostring) + " MB" end)))",
      "  available mem:  \(((($n.availableMemoryBytes // -1) | if . < 0 then "—" else (. / 1048576 * 10 | floor / 10 | tostring) + " MB" end)))",
      "  memory pressure events: \($n.memoryPressureEventCount // 0)",
      "  NOTE: a serious/critical peak thermal means a slow capture may be THROTTLING, not heavy code."
    ] | join("\n")
  end
' "$file"
