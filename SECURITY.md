# Security

This document covers the security posture of the **Argus Unity package** (the contents of this repo). For the **dashboard** security posture see <https://argus-profiler.com/legal/security>.

---

## Why this repo ships only compiled assemblies

The Unity package is distributed as `Argus.Runtime.dll` + `Argus.Editor.dll`. No `.cs` source is included. This raises the cost of two specific abuse scenarios:

1. **Fork-and-self-host** — pointing the wire format at a clone of the dashboard backend with a one-line edit.
2. **Casual reverse engineering** — visible-by-default source makes "delete the URL constant, redistribute as my own" a one-grep operation.

Compiled DLLs don't make these attacks impossible (ILSpy / dotPeek recover readable IL), but they raise the cost from "30 seconds with VS Code" to "decompile first" — which filters out 99% of casual modification.

The deliberate trade-offs:

- **No obfuscation.** Argus relies on `JsonUtility` round-tripping `[Serializable]` types by field name, `[InitializeOnLoad]` discovery of attributed types, and one explicit reflection lookup. Symbol-renaming obfuscation silently breaks all three. We chose correctness over an obfuscation pass that would have produced a fragile product.
- **Public install URL.** The repo is public so Unity Package Manager git-URL installs work without credential setup. Public means the bytes are downloadable; we accept that as the cost of frictionless install.
- **No license phone-home.** The dashboard's per-API-key rate limits, plan-tier quotas, and the dashboard service itself are the commercial moat — not client-side license checks.

If you need source-level access (for an enterprise security review, custom transport, in-house build pipeline), contact <roman@moaigames.io>.

---

## Reporting a vulnerability

Please report security issues privately, not via public issues.

- **Email:** `roman@moaigames.io` (PGP key available on request)
- **GitHub Security Advisories:** open a private advisory on this repo via the **Security** tab
- **Response SLA:** acknowledgement within 2 business days. Fix windows per severity:
  - Critical: 7 days to mitigation, disclosed 30 days later
  - High: 30 days to fix
  - Medium / low: bundled into the next scheduled release

We follow [coordinated disclosure](https://en.wikipedia.org/wiki/Coordinated_disclosure) — public disclosure happens after a fix ships, ideally with a CVE if the impact warrants one.

### What's in scope

- The Unity package shipped in this repo (`Argus.Runtime.dll`, `Argus.Editor.dll`, `package.json`, and bundled Claude integration files)
- Attack paths that originate in a Unity-side capture (e.g. payload crafting that breaks the dashboard's ingest path)
- Authentication / authorisation issues in the runtime upload path

### What's out of scope (report to the dashboard team)

- Dashboard / backend vulnerabilities — report at <https://argus-profiler.com/legal/security>
- Issues with third-party packages we depend on (UniTask, EditorCoroutines) — report upstream
- "API key visible in WebGL bundle" — by design, mitigated via per-key scope + per-key rate limits + per-key origin allowlist (see the docs on platform-typed keys)

---

## Operational security guidance for users

### API keys

- Issue **separate keys per build flavor** (dev / staging / prod). Revoke the dev key when handing off to QA.
- Use **scope-restricted keys** for WebGL builds. The dashboard supports `platform: webgl` keys with an **allowed origins** allowlist — origin-spoofed requests fail at the edge.
- **Rotate** keys periodically. The dashboard exposes a rotation flow that issues a new key with a 24h overlap before revoking the old one.
- **Never** commit a key to a public repo. If you do, revoke it from the dashboard immediately — keys are stored hashed, so the only recovery is reissue.

### Sensitive data in captures

Argus captures performance counters, region labels, scene names, and device fingerprints. It does **NOT** capture:

- Player input / chat / save data
- Screen contents (no screenshots)
- File system contents
- Network packet contents beyond the byte counters in `RunContext.network`

Region labels and event names go to the dashboard as you write them. **Don't put PII or secrets in event names or `uniqueId` values** — they're stored in plaintext on the dashboard.

### Offline mode

When `offlineMode = true` or when uploads fail and `alwaysSaveLocally = true`, captures are written to `ArgusCaptures/` in your project folder. This folder is git-tracked by default — add it to `.gitignore` if your captures contain anything sensitive about your in-progress game.

---

## Disclosure history

| Date | Severity | Summary |
|---|---|---|
| _(no public advisories yet)_ | | |

We'll keep this table current as advisories are published.
