# Architecture — Hayward Monitor (FR)

## Vue d'ensemble

```
┌─────────────────────────── App macOS (SwiftUI) ───────────────────────────┐
│  Vues (Login / Dashboard : jauges + lignes d'équipement)                  │
│        │ @EnvironmentObject                                               │
│  AppModel (@MainActor) — session, polling 30 s, actions de commande       │
│        │ async/await                                                      │
│  HaywardAPI (actor) ──── FirestoreDecoder ──── PoolState (accès typé)     │
│        │ URLSession (HTTPS uniquement)          KeychainStore (identif.)  │
└────────┼──────────────────────────────────────────────────────────────────┘
         │
         ▼  Projet Firebase « hayward-europe »
  ┌─────────────────────────────────────────────────────────────┐
  │ Identity Toolkit  → signInWithPassword / refresh du jeton   │
  │ Firestore REST    → users/{uid} (ids piscine), pools/{id}   │
  │ Cloud Function    → sendPoolCommand (écritures WRP)         │
  └──────────────────────────────┬──────────────────────────────┘
                                 ▼
                    Module WiFi NeoPool → équipements piscine
```

## Choix clés

| Choix | Justification |
|---|---|
| API cloud (pas locale) | Le module WiFi NeoPool ne parle qu'au cloud Hayward ; un accès local exigerait du matériel Modbus supplémentaire. |
| REST pur, pas de SDK Firebase | Surface minuscule (3 endpoints), zéro dépendance SPM, contrôle total des en-têtes (Referer/Origin requis). |
| Polling 30 s | Simple et suffisant pour la télémétrie piscine ; canal Firestore Listen prévu plus tard. |
| Actor pour `HaywardAPI` | Sérialise le refresh de jeton et l'état des requêtes. |
| Refetch post-commande (2 s) | L'UI reflète l'état confirmé par l'appareil, pas une supposition optimiste. |
| Identifiants en Trousseau | Email/mot de passe nécessaires à la ré-auth ; jamais stockés en fichier. |
| Consigne éditée dans le popover de sa jauge | La valeur se règle là où elle se lit ; supprime la section « Consignes » et le scroll qu'elle imposait. |
| `pendingPaths` dans `AppModel` | Le boîtier met ~20 s à confirmer : la ligne touchée affiche un spinner au lieu de laisser croire que rien ne se passe. |
| Auto-update Sparkle 2 | Appcast signé EdDSA servi depuis le repo (`main/appcast.xml`) ; vérifications en arrière-plan seulement, installation toujours avec consentement. App sandboxée → service XPC InstallerLauncher + exceptions mach-lookup. |

## Protocole d'écriture

`setValue(path, value)` clone la branche du document contenant `path`
(réduite à 2 niveaux pour les chemins profonds comme
`relays.relay1.info.onoff`), la modifie, puis POST :

```json
{
  "gateway": "<id wifi piscine>",
  "poolId": "<id>",
  "operation": "WRP",
  "changes": "<branche JSON en chaîne>",
  "source": "web"
}
```

Cas particulier : `hidro.cloration_enabled` (boost) positionne aussi
`reduction` et `disable=1`, comme le client web officiel.

## Échelles des données

| Chemin | Échelle | Unité |
|---|---|---|
| `main.temperature` | ×1 | °C |
| `modules.ph.current`, `ph.status.*` | ÷100 | pH |
| `modules.rx.current`, `rx.status.value` | ×1 | mV |
| `hidro.current`, `hidro.level` | ÷10 | g/h |
| `filtration.mode` | enum | 0=Manuel 1=Auto 2=Chauffage 3=Smart 4=Intel |
