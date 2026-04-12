# Setup Juno pe iPhone

## Ce face versiunea Juno

| Funcție | Status |
|---|---|
| Învață din YouTube (căutare/URL) | ✅ Funcționează pe iPhone |
| Analizează screenshot și dă sfaturi | ✅ Funcționează pe iPhone |
| Salvează strategii local | ✅ Funcționează pe iPhone |
| Joacă automat (bot full auto) | ❌ Imposibil pe iOS fără jailbreak |

---

## Instalare (5 minute)

### 1. Descarcă Juno IDE
App Store → caută **Juno for Jupyter** → instalează (gratuit cu cumpărare in-app pentru notebook-uri)

### 2. Copiază fișierele botului în Juno
- Descarcă folderul `bot/juno/` din repo
- **Files app** → On My iPhone → Juno → copiază:
  - `bot.ipynb`
  - `kb.py`
  - `youtube_learn.py`
  - `game_advisor.py`

### 3. Deschide `bot.ipynb` în Juno
- Pune **API key-ul** tău în prima celulă:
  ```python
  API_KEY = 'sk-ant-api03-...'
  ```
  Obții cheia de la: **console.anthropic.com** → API Keys

### 4. Rulează celula de Setup (prima celulă)
- Apasă ▶ sau Shift+Enter
- Instalează automat: `anthropic`, `yt-dlp`, `Pillow`
- Durează ~1 minut prima dată

---

## Cum înveți din YouTube

1. Deschide `bot.ipynb` în Juno
2. Rulează celula **"Învață din YouTube"**
3. Modifică query-ul:
   ```python
   query = 'dota underlords best strategy guide 2024'
   ```
4. Rulează → botul caută, descarcă subtitrările, Claude extrage strategiile
5. Se salvează automat în `knowledge_base.json`

**Nu are nevoie de WiFi puternic** — descarcă doar text (subtitrări), nu video.

---

## Cum folosești Screenshot Advisor

### Pasul cu pasul:
1. Ești în Dota Underlords, vrei sfat
2. **Power + Volume Up** → screenshot
3. **Files app** → Photos → selectează screenshot → ⋯ → Move → Juno
4. Redenumește-l `screenshot.png` (sau orice nume simplu)
5. Deschide **Juno** → `bot.ipynb`
6. Rulează celula **"Sfat în timp real"**
7. Introdu numele fișierului când ți se cere

### Rezultat:
```
═══════════════════════════════════════════
🤖 RECOMANDARE BOT
═══════════════════════════════════════════
## Situatia curenta
- Gold: 8 | HP: 74 | Runda: 12 | Level: 5
- Eroi în shop: Axe, Dragon Knight, Luna, ...
- Alianțe active: Warriors x2

## Recomandare imediată
**CUMPARA Dragon Knight din slot 2** (cost 3 gold,
completează Warriors x3 → activezi bonus armor +10)

## De ce
Ai 8 gold, Dragon Knight completează alianta Warriors
care îți dă +10 armor la toți eroii. Prioritate mare.

## Urmatorii pași
1. Cumpara DK → pune pe tablă în față
2. Lock shop (ai combo bun)
3. Round 13: level up dacă ai 10+ gold
═══════════════════════════════════════════
```

---

## Shortcut iOS (opțional — workflow ultra rapid)

### Setup Back Tap:
1. **Settings** → **Accessibility** → **Touch** → **Back Tap**
2. **Triple Tap** → **Take Screenshot**

### Shortcut automat (Shortcuts app):
1. **+** → New Shortcut
2. **Take Screenshot** → salvează în Files → Juno → `latest.png`
3. Adaugă **Open App** → Juno

Acum: **3 tapuri pe spatele iPhone-ului** → screenshot în Juno folder → deschide Juno → rulezi analiza pe `latest.png`.

---

## Limitări iOS

- **Nu poate juca automat** — iOS nu permite controlul altor aplicații
- **Nu poate captura ecranul automat** — iOS sandbox
- **Juno trebuie deschis** pentru a rula analiza (nu funcționează în background)
- **Whisper nu merge** pe iOS (prea greu) — folosim subtitrări YouTube în schimb

## FAQ

**Q: Yt-dlp merge pe iPhone?**  
A: Da, e scris în Python pur. Juno îl poate instala și rula.

**Q: Pot salva knowledge_base.json pe iCloud?**  
A: Da, din Files app poți muta fișierul în iCloud Drive pentru backup automat.

**Q: Funcționează fără internet pentru analiză?**  
A: Nu — Claude API necesită internet. YouTube learning necesită internet.
