# Argus README screenshots

PNGs referenced by `../README.md` (and `argus-control-overview.png` by `Assets/Argus/README.md`). Drop them into this folder before publishing; the Releaser copies the folder into the package.

| File | What to capture |
|---|---|
| `argus-control-overview.png` | Argus Control window, **● CONNECTED**, sections expanded. |
| `argus-control-sections-menu.png` | The **Sections ▾** menu open (section checkmarks, Expand all / Collapse all / Reset to automatic). |
| `argus-control-collapsed.png` | Connection collapsed to its summary line (e.g. `● CONNECTED · auto-connect`). |
| `argus-control-connection.png` | Connection card: status pill, Offline, Auto-connect on Unity load, masked API key with **Edit**, Connect / Disconnect. |
| `argus-control-devices.png` | Devices card with device rows (streaming / idle) and the Add device panel (Scan Wi-Fi, pinned IPs, iOS / direct IP). |
| `argus-control-session-capture.png` | Test Session card (Label, Environment, End Session Now) and Capture card. |
| `argus-control-advanced.png` | Advanced card: config readout, Multi-Device Mode, ARGUS_ENABLED buttons, Regenerate config defaults, Native Trace (Pro). |
| `argus-config-inspector.png` | `ArgusConfig` asset in the Inspector. |
| `dashboard-session-detail.png` | A session detail page on argus-profiler.com with the frame-timeline chart visible. |

The README is laid out so missing images degrade gracefully (broken-image icon, surrounding text still reads).

Recommended: max 1200px wide, PNG-24, each file < 200 KB where possible.
