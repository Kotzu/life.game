"""
Game Advisor - analizeaza screenshot-uri din Juno/iPhone.

Cum functionezi:
  1. Esti in Underlords, vrei sfat
  2. Faci screenshot (buton Power + Volume Up)
  3. Deschizi Juno si rulezi ask()
  4. Selectezi screenshot-ul din Photos
  5. Claude iti spune exact ce sa faci

Sau folosesti iOS Shortcuts pentru automatizare:
  - Shortcut: Screenshot → Share → Run Script in Juno
  - Botul iti raspunde cu recomandarea

Utilizare in Juno:
  advisor = GameAdvisor(api_key="sk-ant-...")
  advisor.ask()           # te ghideaza sa selectezi screenshot
  advisor.ask(path="...")  # analizeaza un fisier direct
"""

import base64
import io
import os
from pathlib import Path
from typing import Optional

import anthropic


UNDERLORDS_SYSTEM = """Esti un expert la Dota Underlords (auto-battler de la Valve).

Cand analizezi un screenshot, raspunde INTOTDEAUNA cu:

## Situatia curenta
- Gold: X | HP: X | Runda: X | Level: X
- Eroi in shop: [lista]
- Eroi pe tabla: [lista]
- Aliante active: [lista]

## Recomandare imediata
**Actiunea urmatoare** (BOLD, clara si specifica):
Ex: "CUMPARA Dragon Knight din slot 2 (cost 3 gold, completeaza Knights x3)"

## De ce
Explica pe scurt ratiunea (1-2 propozitii).

## Urmatorii pasi
3 pasi urmatori in ordine de prioritate.

Fii DIRECT si SPECIFIC. Nu vorbi vag. Spune exact ce buton/slot/erou.
"""


class GameAdvisor:
    """Advisor bazat pe Claude Vision pentru Dota Underlords."""

    def __init__(self, api_key: str, game: str = "dota_underlords"):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.game = game
        self.history = []  # Istoricul recomandarilor din sesiunea curenta

    def ask(self, path: Optional[str] = None, knowledge: str = "") -> str:
        """
        Analizeaza un screenshot si da recomandare.

        Args:
            path: Calea catre screenshot. Daca None, cere manual.
            knowledge: Cunostinte din knowledge base (optional).

        Returns:
            Recomandarea ca text.
        """
        # Obtine imaginea
        if path is None:
            path = self._prompt_for_path()
        if path is None:
            return "❌ Niciun screenshot selectat."

        img_b64, media_type = self._load_image(path)
        if img_b64 is None:
            return f"❌ Nu pot incarca imaginea: {path}"

        print(f"🔍 Analizez screenshot-ul... ({Path(path).name})")

        # Construieste mesajul
        user_text = "Analizeaza acest screenshot din Dota Underlords si da-mi recomandarea ta."
        if knowledge:
            user_text += f"\n\nCunostinte de care sa tii cont:\n{knowledge[:2000]}"
        if self.history:
            last = self.history[-1]
            user_text += f"\n\nUltima recomandare data: {last[:200]}"

        try:
            msg = self.client.messages.create(
                model="claude-opus-4-6",
                max_tokens=1024,
                system=UNDERLORDS_SYSTEM,
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": img_b64,
                            },
                        },
                        {"type": "text", "text": user_text},
                    ],
                }],
            )
            result = msg.content[0].text
            self.history.append(result)
            self._print_recommendation(result)
            return result

        except anthropic.APIError as e:
            err = f"❌ Eroare API: {e}"
            print(err)
            return err

    def ask_with_kb(self, path: Optional[str] = None, kb=None) -> str:
        """Analizeaza screenshot-ul folosind si cunostintele din knowledge base."""
        knowledge = ""
        if kb:
            knowledge = kb.get_all_knowledge(self.game)
        return self.ask(path=path, knowledge=knowledge)

    def describe(self, path: Optional[str] = None) -> str:
        """Descriere generala a screenshot-ului (pentru debug)."""
        if path is None:
            path = self._prompt_for_path()
        if path is None:
            return "❌ Niciun screenshot."

        img_b64, media_type = self._load_image(path)
        if img_b64 is None:
            return "❌ Nu pot incarca imaginea."

        msg = self.client.messages.create(
            model="claude-opus-4-6",
            max_tokens=512,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": img_b64,
                        },
                    },
                    {"type": "text", "text": "Descrie ce vezi in aceasta imagine (joc, UI, resurse, etc.)"},
                ],
            }],
        )
        result = msg.content[0].text
        print(result)
        return result

    # ===== INTERNE =====

    def _prompt_for_path(self) -> Optional[str]:
        """Cere utilizatorului sa introduca calea screenshot-ului."""
        print("\n📸 Screenshot Advisor")
        print("─" * 40)
        print("Introdu calea catre screenshot:")
        print("  • In Juno: fisierele sunt in Documents/")
        print("  • Copiaza screenshot din Photos -> Files -> Juno folder")
        print("  • Sau introdu calea completa")
        print()
        path = input("Cale: ").strip().strip('"').strip("'")
        if not path:
            return None
        # Expandeaza ~ si verifica existenta
        path = os.path.expanduser(path)
        if not os.path.exists(path):
            # Incearca in directorul curent
            local = os.path.join(os.getcwd(), path)
            if os.path.exists(local):
                return local
            print(f"❌ Fisierul nu exista: {path}")
            return None
        return path

    def _load_image(self, path: str):
        """Incarca si comprima imaginea pentru Claude API."""
        try:
            from PIL import Image

            img = Image.open(path).convert("RGB")

            # Resize daca e prea mare (iPhone face screenshots 1290x2796)
            max_width = 1024
            if img.width > max_width:
                ratio = max_width / img.width
                img = img.resize((max_width, int(img.height * ratio)), Image.LANCZOS)

            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=85)
            b64 = base64.b64encode(buf.getvalue()).decode()
            return b64, "image/jpeg"

        except ImportError:
            # Fara Pillow: incarca raw si trimite ca PNG
            with open(path, "rb") as f:
                data = f.read()
            b64 = base64.b64encode(data).decode()
            ext = Path(path).suffix.lower()
            media_type = {
                ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                ".png": "image/png", ".webp": "image/webp",
            }.get(ext, "image/jpeg")
            return b64, media_type

        except Exception as e:
            print(f"Eroare incarcare imagine: {e}")
            return None, None

    def _print_recommendation(self, text: str):
        """Afiseaza recomandarea formatat frumos."""
        print("\n" + "═" * 50)
        print("🤖 RECOMANDARE BOT")
        print("═" * 50)
        print(text)
        print("═" * 50 + "\n")
