# Hayward Monitor

Native macOS app (SwiftUI) to monitor and control a Hayward AquaRite /
Sugar Valley NeoPool swimming-pool system — the same device managed by the
PoolWatch / Vistapool iPhone apps.

## Features

| Feature | Status |
|---|---|
| Sign in with PoolWatch / Vistapool account (Keychain-stored) | ✅ |
| Live dashboard: temperature, pH, redox, chlorine, electrolysis, WiFi | ✅ |
| Filtration on/off, pump mode & speed | ✅ |
| Pool light, electrolysis boost, cover mode, aux relays 1-4 | ✅ |
| Setpoints: pH min/max, redox, electrolysis production | ✅ |
| Auto-refresh (30 s polling) | ✅ |
| Menu bar extra, real-time push, history charts | 🔜 |

## How it works

The Hayward Europe cloud is a Firebase project (`hayward-europe`). The app
talks to it directly over REST — no Firebase SDK:

- **Auth**: Google Identity Toolkit (email/password of your PoolWatch account)
- **Reads**: Firestore REST (`pools/{poolId}` document)
- **Writes**: `sendPoolCommand` Cloud Function (WRP operation)

Protocol reference: [aioaquarite](https://pypi.org/project/aioaquarite/) /
[fdebrus/hayward-ha](https://github.com/fdebrus/hayward-ha).

## Build

```bash
xcodegen generate
xcodebuild -scheme HaywardMonitor -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Requires macOS 14+, Xcode, xcodegen.

## Project layout

```
HaywardMonitor/
├── project.yml                 # xcodegen definition
└── HaywardMonitor/
    ├── HaywardMonitorApp.swift
    ├── Models/PoolState.swift      # typed view over the pool document
    ├── Services/
    │   ├── HaywardAPI.swift        # auth + Firestore + commands (actor)
    │   ├── FirestoreDecoder.swift  # Firestore REST envelope decoding
    │   └── KeychainStore.swift
    ├── ViewModels/AppModel.swift   # session, polling, command actions
    └── Views/                      # Login, Dashboard, Setpoints
```

## Roadmap

- [x] MVP: dashboard + controls + setpoints (v0.1.0)
- [ ] Real-account validation
- [ ] Menu bar extra
- [ ] Firestore real-time listen (replace polling)
- [ ] History charts & notifications
- [ ] Signed & notarized release DMG
