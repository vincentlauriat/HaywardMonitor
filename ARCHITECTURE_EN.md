# Architecture — Hayward Monitor

## Overview

```
┌─────────────────────────── macOS app (SwiftUI) ───────────────────────────┐
│  Views (Login / Dashboard: gauges + device rows)                          │
│        │ @EnvironmentObject                                               │
│  AppModel (@MainActor) — session, 30 s polling, command actions           │
│        │ async/await                                                      │
│  HaywardAPI (actor) ──── FirestoreDecoder ──── PoolState (typed access)   │
│        │ URLSession (HTTPS only)                KeychainStore (creds)     │
└────────┼──────────────────────────────────────────────────────────────────┘
         │
         ▼  Firebase project «hayward-europe»
  ┌─────────────────────────────────────────────────────────────┐
  │ Identity Toolkit  → signInWithPassword / token refresh      │
  │ Firestore REST    → users/{uid} (pool ids), pools/{poolId}  │
  │ Cloud Function    → sendPoolCommand (WRP writes)            │
  └──────────────────────────────┬──────────────────────────────┘
                                 ▼
                    NeoPool WiFi module → pool hardware
```

## Key choices

| Choice | Rationale |
|---|---|
| Cloud API (not local) | The NeoPool WiFi module only talks to the Hayward cloud; local access would require extra Modbus hardware. |
| Pure REST, no Firebase SDK | Tiny surface (3 endpoints), zero SPM dependencies, full control over auth headers (Referer/Origin required). |
| 30 s polling | Simple and sufficient for pool telemetry; Firestore Listen channel planned later. |
| Actor for `HaywardAPI` | Serializes token refresh and request state. |
| Post-command refetch (2 s) | UI reflects device-acknowledged state instead of optimistic guesses. |
| Keychain credentials | Email/password needed for re-auth; never stored in files. |
| Setpoint edited in its gauge's popover | A value is adjusted where it is read; removes the separate "Setpoints" section and the scrolling it forced. |
| `pendingPaths` in `AppModel` | The box takes ~20 s to acknowledge: the row that was touched shows a spinner instead of implying nothing happened. |
| Sparkle 2 auto-update | EdDSA-signed appcast served from the repo (`main/appcast.xml`); background checks only, install always requires user consent. Sandboxed app → InstallerLauncher XPC service + mach-lookup exceptions. |

## Write protocol

`setValue(path, value)` clones the document branch containing `path`
(narrowed to 2 levels for deep paths like `relays.relay1.info.onoff`),
mutates it, and POSTs:

```json
{
  "gateway": "<pool wifi id>",
  "poolId": "<id>",
  "operation": "WRP",
  "changes": "<JSON branch as string>",
  "source": "web"
}
```

Special case: `hidro.cloration_enabled` (boost) also sets `reduction` and
`disable=1`, mirroring the official web client.

## Data scales

| Path | Scale | Unit |
|---|---|---|
| `main.temperature` | ×1 | °C |
| `modules.ph.current`, `ph.status.*` | ÷100 | pH |
| `modules.rx.current`, `rx.status.value` | ×1 | mV |
| `hidro.current`, `hidro.level` | ÷10 | g/h |
| `filtration.mode` | enum | 0=Manual 1=Auto 2=Heat 3=Smart 4=Intel |
