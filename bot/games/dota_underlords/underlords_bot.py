"""
Dota Underlords Bot - Implementare specifica pentru Dota Underlords.
Auto-battler game: pozitionare eroi, cumparare din shop, reroll, level up.

Starea jocului:
- Gold (resura principala)
- HP (viata jucatorului)
- Round (runda curenta)
- Level (nivelul jucatorului -> slots pe tabla)
- Shop (5 eroi disponibili pentru cumparare)
- Bench (banca: eroi cumparati dar nepositionati)
- Board (tabla: eroi activi in lupta)
"""

import json
import re
from typing import Any, Dict, List, Optional

from games.base_game import BaseGame
from utils.logger import log


UNDERLORDS_SYSTEM_PROMPT = """Esti un expert la Dota Underlords, jocul auto-battler de la Valve.

CONTEXT JOC:
- E un auto-battler: iti construiesti o echipa de eroi, ei lupta automat
- Ai un numar limitat de slot-uri pe tabla (= nivelul tau)
- Shop-ul ofera 5 eroi aleatoriu. Poti cumpara, reroll sau skip
- Combinand 3 copii ale aceluiasi erou obtii versiunea 2 stele (mai puternica)
- Aliantele: eroii din aceeasi alianta se combina pentru bonusuri
- Obiectiv: sa supravietuiesti si sa elimini adversarii

PRIORITATI:
1. Nu risipi gold (interes compus: 10 gold = +1 gold/runda)
2. Cauta combinatii de 3 pentru upgrade eroi
3. Pastreaza sinergii (aliantele active = bonusuri mari)
4. Reroll numai daca ai destul gold sau ai nevoie urgenta de un erou
5. Level up la momentul potrivit (nu prea devreme)
6. Pozitioneaza inteligent: tanky in fata, carry in spate

ACTIUNI DISPONIBILE:
- buy: cumpara un erou din shop (costa gold)
- sell: vinde un erou de pe banca/tabla (recupereaza 1 gold)
- place: muta un erou de pe banca pe tabla
- reroll: reinnoieste shop-ul (costa 2 gold)
- level_up: creste nivelul (costa gold = nivel curent)
- lock: blocheaza/deblocheaza shop-ul
- wait: asteapta (nu face nimic)

Raspunde EXCLUSIV cu JSON valid.
"""


class UnderlordsBot(BaseGame):
    """Bot specific pentru Dota Underlords."""

    @property
    def game_name(self) -> str:
        return "dota_underlords"

    def get_system_prompt(self) -> str:
        return UNDERLORDS_SYSTEM_PROMPT

    def parse_game_state(self, screenshot_b64: str) -> Dict[str, Any]:
        """
        Extrage starea jocului din screenshot folosind Claude Vision.
        Cauta: gold, hp, round, level, shop heroes, board heroes.
        """
        analysis_prompt = """Analizeaza acest screenshot din Dota Underlords si extrage:
1. Gold curent (numarul galben din UI)
2. HP curent al jucatorului
3. Runda curenta
4. Nivelul jucatorului
5. Eroii din shop (cei 5 din bara de jos)
6. Eroii pe tabla (daca sunt vizibili)
7. Eroii pe banca (sub tabla)
8. Daca shop-ul e blocat sau nu
9. Faza curenta (planning/combat/shopping)

Returneaza STRICT un JSON cu structura:
{
  "gold": <int>,
  "hp": <int>,
  "round": <int>,
  "level": <int>,
  "xp_current": <int>,
  "xp_needed": <int>,
  "shop": [
    {"name": "<hero_name>", "cost": <int>, "tier": <1-5>}
  ],
  "board": [
    {"name": "<hero_name>", "stars": <1-3>, "position": "<e.g. front-left>"}
  ],
  "bench": [
    {"name": "<hero_name>", "stars": <1-3>}
  ],
  "shop_locked": <bool>,
  "phase": "planning|combat|shopping|unknown",
  "notes": "<orice observatie importanta>"
}
Daca nu poti citi o valoare, foloseste null.
"""
        result = self.vision.analyze_game_state(
            screenshot_b64=screenshot_b64,
            game_context=analysis_prompt,
            system_prompt=UNDERLORDS_SYSTEM_PROMPT,
        )

        # Parse JSON din raspunsul raw
        raw = result.get("raw_response", "{}")
        game_state = self._parse_state_json(raw)
        game_state["game"] = self.game_name
        return game_state

    def execute_action(self, action: Dict[str, Any]) -> bool:
        """
        Executa o actiune specifica Dota Underlords.
        Mapeaza actiunile LLM la click-uri reale pe UI.
        """
        action_type = action.get("action", "wait")
        log.info(f"Execut actiune: {action_type} | Motiv: {action.get('reason', 'N/A')}")

        try:
            if action_type == "wait":
                self.input.pause()
                return True

            elif action_type == "buy":
                return self._buy_hero(action)

            elif action_type == "sell":
                return self._sell_hero(action)

            elif action_type == "reroll":
                return self._reroll_shop()

            elif action_type == "level_up":
                return self._level_up()

            elif action_type == "place":
                return self._place_hero(action)

            elif action_type == "lock":
                return self._toggle_lock_shop()

            elif action_type == "click":
                # Actiune generica click
                x = action.get("x")
                y = action.get("y")
                if x and y:
                    self.input.click(int(x), int(y))
                    return True
                return False

            elif action_type == "drag":
                # Drag generic
                fx, fy = action.get("from_x"), action.get("from_y")
                tx, ty = action.get("x"), action.get("y")
                if all([fx, fy, tx, ty]):
                    self.input.drag(int(fx), int(fy), int(tx), int(ty))
                    return True
                return False

            else:
                log.warning(f"Actiune necunoscuta: {action_type}")
                return False

        except Exception as e:
            log.error(f"Eroare la executarea actiunii {action_type}: {e}")
            return False

    def is_game_active(self, screenshot_b64: str) -> bool:
        """Verifica daca Dota Underlords e activ pe ecran."""
        desc = self.vision.describe_scene(screenshot_b64)
        keywords = ["underlords", "gold", "shop", "round", "hero", "dota"]
        desc_lower = desc.lower()
        found = sum(1 for kw in keywords if kw in desc_lower)
        return found >= 2

    # ===== Actiuni specifice Dota Underlords =====

    def _buy_hero(self, action: Dict) -> bool:
        """Cumpara un erou din shop."""
        # Shop-ul are 5 slot-uri, distribuite orizontal in partea de jos
        # Coordonate aproximative ale shop-ului (% din ecran)
        shop_slots_x = [0.18, 0.32, 0.46, 0.60, 0.74]  # X pentru fiecare slot
        shop_y = 0.92  # Y fix pentru shop

        slot_index = action.get("shop_slot", action.get("slot_index"))

        if slot_index is not None and 0 <= int(slot_index) < 5:
            idx = int(slot_index)
            x, y = self._pct_to_px(shop_slots_x[idx], shop_y)
            self.input.click(x, y)
            self.input.pause()
            log.info(f"Cumpar eroul din slot {idx} la ({x}, {y})")
            return True

        # Daca nu stim slot-ul, folosim coordonatele directe
        x, y = action.get("x"), action.get("y")
        if x and y:
            self.input.click(int(x), int(y))
            return True

        log.warning("Nu stiu unde sa cumpar eroul - lipsesc coordonatele")
        return False

    def _sell_hero(self, action: Dict) -> bool:
        """Vinde un erou (drag pe icona de vanzare sau click dreapta)."""
        x, y = action.get("x"), action.get("y")
        if x and y:
            # In Underlords: drag eroul afara din tabla/banca pentru vanzare
            sell_x, sell_y = self._pct_to_px(0.5, 0.98)  # Zona de vanzare (jos-centru)
            self.input.drag(int(x), int(y), sell_x, sell_y)
            self.input.pause()
            return True
        return False

    def _reroll_shop(self) -> bool:
        """Apasa butonul de reroll (costa 2 gold)."""
        # Butonul Reroll e in stanga shop-ului, de obicei
        reroll_x, reroll_y = self._pct_to_px(0.07, 0.92)
        self.input.click(reroll_x, reroll_y)
        self.input.pause()
        log.info("Reroll shop")
        return True

    def _level_up(self) -> bool:
        """Apasa butonul de level up."""
        # Butonul Level Up e in stanga, langa experienta
        levelup_x, levelup_y = self._pct_to_px(0.07, 0.96)
        self.input.click(levelup_x, levelup_y)
        self.input.pause()
        log.info("Level Up apasata")
        return True

    def _place_hero(self, action: Dict) -> bool:
        """Muta un erou de pe banca pe tabla (drag)."""
        from_x = action.get("from_x") or action.get("x")
        from_y = action.get("from_y") or action.get("y")
        to_x = action.get("to_x")
        to_y = action.get("to_y")

        if all([from_x, from_y, to_x, to_y]):
            self.input.drag(int(from_x), int(from_y), int(to_x), int(to_y))
            self.input.pause()
            return True

        log.warning("Lipsesc coordonatele pentru place hero")
        return False

    def _toggle_lock_shop(self) -> bool:
        """Toggle lock/unlock shop."""
        lock_x, lock_y = self._pct_to_px(0.07, 0.89)
        self.input.click(lock_x, lock_y)
        return True

    def _parse_state_json(self, raw_text: str) -> Dict:
        """Extrage JSON din raspunsul LLM."""
        json_match = re.search(r'\{.*\}', raw_text, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group())
            except json.JSONDecodeError as e:
                log.warning(f"JSON invalid in raspuns: {e}")

        # Fallback: stare goala
        return {
            "gold": None,
            "hp": None,
            "round": None,
            "level": None,
            "shop": [],
            "board": [],
            "bench": [],
            "shop_locked": False,
            "phase": "unknown",
            "notes": "Nu s-a putut parsa starea jocului",
        }
