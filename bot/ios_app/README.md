# BotBridge – iOS App

Aplicație nativă Swift care:
- **Capturează ecranul** via ReplayKit (fără jailbreak, fără Developer Mode)
- **Trimite frames** la Claude Vision API direct de pe iPhone
- **Afișează recomandări** în **Dynamic Island** (mereu vizibil deasupra jocului)
- **Touch injection** opțional via XCTest (necesită Developer Mode)

## Ce face fiecare componentă

| Fișier | Rol |
|---|---|
| `Sources/ScreenCapture.swift` | ReplayKit → JPEG frames |
| `Sources/ClaudeAPI.swift` | Apel Claude Vision API |
| `Sources/BotLoop.swift` | Loop: captura → Claude → Dynamic Island |
| `Sources/BotActivity.swift` | Model Live Activity (shared) |
| `Sources/ContentView.swift` | UI setup (API key, start/stop, log) |
| `Widget/BotWidget.swift` | Dynamic Island + Lock Screen widget |
| `Touch/TouchRunner.swift` | XCTest touch injection (opțional) |

## Dynamic Island în acțiune

```
┌─────────────────────────────────────┐
│  [●●●] brain  CUMPARA  buy  87%    │  ← Compact
└─────────────────────────────────────┘

Expand (long press):
┌─────────────────────────────────────┐
│  BOT 🧠                        87%  │
│    CUMPARA Dragon Knight slot 2     │
│    8g ●  74hp ♥         BUY        │
└─────────────────────────────────────┘
```

## Build – Varianta 1: GitHub Actions (fără Mac)

1. **Fork** repo-ul pe GitHub (trebuie să fie public sau ai GitHub Pro)
2. Du-te la **Actions** → **Build BotBridge IPA** → **Run workflow**
3. Descarcă `BotBridge-unsigned.ipa` din artifacts
4. Sideload cu **AltStore** sau **SideStore** pe iPhone

## Build – Varianta 2: Mac cu Xcode

```bash
# Instalează XcodeGen
brew install xcodegen

# Generează proiectul Xcode
cd bot/ios_app
xcodegen generate

# Deschide în Xcode
open BotBridge.xcodeproj
# → Selectează team-ul tău (Apple ID gratuit funcționează)
# → Product → Run
```

## Sideload cu AltStore (fără Mac, fără jailbreak)

1. Instalează **AltServer** pe Windows sau Mac
2. Instalează **AltStore** pe iPhone din AltServer
3. În AltStore: **+** → selectează `BotBridge-unsigned.ipa`
4. Semnează cu Apple ID-ul tău (gratuit)
5. Valabil 7 zile (refresh automat cu AltStore)

## Utilizare

1. Deschide **BotBridge** pe iPhone
2. Introdu API key-ul tău Anthropic
3. Apasă **Pornește**
4. Acordă permisiunea pentru **Screen Recording** (prima dată)
5. Minimizează BotBridge și deschide **Dota Underlords**
6. **Dynamic Island** arată recomandările în timp real

## Touch injection (opțional, necesită Developer Mode)

Developer Mode pe iPhone 16 Pro Max:
```
Conectează iPhone la Mac cu Xcode →
Settings → Privacy & Security → Developer Mode → ON
```

Odată activat, build-ul cu targetul `BotBridgeTouch` permite touch-uri automate.

## Permisiuni necesare

| Permisiune | Când e cerută | De ce |
|---|---|---|
| Screen Recording | Prima lansare | ReplayKit capturează ecranul |
| Live Activities | Automat din Settings | Dynamic Island |

Nu sunt necesare: Camera, Microfon, Locație, Contacte.

## Partajare knowledge base cu Juno

Fișierele JSON sunt în același App Group:
- **BotBridge** scrie în `group.com.aibot.BotBridge/knowledge_base.json`
- **Juno** poate citi același fișier dacă setezi calea corectă

Sau: exportă din Files app → transferă via AirDrop/iCloud.
