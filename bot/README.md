# Universal AI Game Bot

Bot universal cu creier AI (Claude LLM + Vision) pentru jocuri single-player/offline.
Invata strategii din YouTube si joaca automat.

## Arhitectura

```
bot/
├── main.py                          # Entry point principal
├── requirements.txt                 # Dependinte Python
├── config/
│   └── settings.yaml               # Configuratie globala
├── core/
│   ├── screen_capture.py           # Captura ecran (MSS, stealthy)
│   ├── input_controller.py         # Mouse/tastatura cu miscare umana (bezier)
│   ├── vision_analyzer.py          # Claude Vision API
│   └── decision_engine.py          # Creierul: LLM decide actiunile
├── learning/
│   ├── youtube_learner.py          # Invata strategii din YouTube
│   └── knowledge_base.py          # Baza de cunostinte persistenta
├── games/
│   ├── base_game.py               # Clasa de baza (template)
│   └── dota_underlords/
│       └── underlords_bot.py      # Bot specific Dota Underlords
└── utils/
    ├── logger.py                  # Logger (loguru + rich)
    └── config.py                  # Config loader (YAML)
```

## Instalare

```bash
cd bot/
pip install -r requirements.txt
```

## Setup

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

## Utilizare

### 1. Joaca Dota Underlords
```bash
# Porneste jocul, minimizeaza sau pune-l fullscreen
# Ruleaza botul:
python main.py --game dota_underlords
```

### 2. Invata din YouTube inainte de a juca
```bash
python main.py --game dota_underlords \
  --learn-url "https://www.youtube.com/watch?v=<video_id>"
```

### 3. Invata din mai multe video-uri
```bash
# Ruleaza de mai multe ori cu URL-uri diferite
python main.py --game dota_underlords --learn-url "URL1"
python main.py --game dota_underlords --learn-url "URL2"
```

### 4. Adauga strategii manual
```bash
python main.py --game dota_underlords \
  --add-strategy "Prioritizeaza aliantele Warriors + Assassins early game"
```

### 5. Debug - descrie ce vede botul
```bash
python main.py --describe
```

### 6. Statistici knowledge base
```bash
python main.py --kb-stats
```

## Cum functioneaza

```
┌─────────────────────────────────────────────────────────┐
│                    LOOP PRINCIPAL                        │
│                                                         │
│  Ecran ──► MSS Capture ──► Base64 JPEG                 │
│                                    │                    │
│                                    ▼                    │
│                         Claude Vision API               │
│                         (parse game state)              │
│                                    │                    │
│                                    ▼                    │
│                     Knowledge Base + History            │
│                     (strategii YouTube + experienta)    │
│                                    │                    │
│                                    ▼                    │
│                         Claude LLM Decision             │
│                         (ce actiune sa faca)            │
│                                    │                    │
│                                    ▼                    │
│                     pynput Mouse/Keyboard               │
│                     (miscare bezier, timing uman)       │
│                                    │                    │
│                                    └──────► REPETA      │
└─────────────────────────────────────────────────────────┘
```

## Caracteristici "Undetected" (pentru jocuri offline)

- **MSS** pentru screen capture: foloseste DirectX/X11 direct, nu window hooks
- **pynput** pentru input: low-level OS APIs (evdev pe Linux, Win32 pe Windows)
- **Bezier mouse movement**: miscarea mouse-ului urmeaza curbe naturale
- **Timing randomizat**: delay-uri random intre actiuni (nu pattern fix)
- **Fara injectie de cod**: totul e facut din exterior, prin UI

## Adauga un Joc Nou

1. Creeaza `games/new_game/new_game_bot.py`
2. Extinde `BaseGame`
3. Implementeaza: `game_name`, `parse_game_state`, `execute_action`, `is_game_active`
4. Adauga in factory-ul din `main.py`

## Modele AI Suportate

- `claude-opus-4-6` (recomandat, cel mai capabil)
- `claude-sonnet-4-6` (mai rapid, mai ieftin)

Configureaza in `config/settings.yaml`.
