"""
Decision Engine - Creierul botului.
Combina viziunea, cunostintele si starea jocului pentru decizii optime.
"""

import json
import re
import time
from typing import Any, Dict, List, Optional

import anthropic

from utils.logger import log


DECISION_SYSTEM_PROMPT = """Esti un AI expert in jocuri video. Rolul tau este sa joci jocuri single-player offline
la nivel optim. Ai acces la:
1. Screenshot-uri ale jocului in timp real
2. Starea curenta a jocului (resurse, unitati, etc.)
3. Strategii si cunostinte invatate din gameplay-uri de pe YouTube

Reguli de baza:
- Ia decizii rapide si eficiente
- Prioritizeaza actiunile cu impact maxim
- Nu repeta actiuni care nu au dat rezultat
- Adapteaza-te la situatia curenta
- Raspunde DOAR cu JSON valid, fara alt text
"""


class DecisionEngine:
    """
    Motor de decizie bazat pe LLM.
    Proceseaza starea jocului si genereaza actiuni.
    """

    def __init__(self, config: dict, knowledge_base):
        import os
        api_key = os.environ.get(config["ai"]["api_key_env"])
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = config["ai"]["model"]
        self.knowledge_base = knowledge_base
        self.history: List[Dict] = []  # Istoricul actiunilor recente
        self.max_history = 10

        log.info(f"DecisionEngine initializat cu {self.model}")

    def decide(
        self,
        game_state: Dict[str, Any],
        screenshot_b64: str,
        game_name: str,
    ) -> Dict[str, Any]:
        """
        Decide urmatoarea actiune bazata pe starea jocului.

        Returns:
            {
                "action": "click|drag|key|wait|reroll|buy|sell|place|combine",
                "x": int|None,
                "y": int|None,
                "from_x": int|None,  # pentru drag
                "from_y": int|None,
                "key": str|None,     # pentru key press
                "reason": str,
                "confidence": float
            }
        """
        # Obtine cunostinte relevante
        knowledge = self.knowledge_base.get_relevant_knowledge(game_name, game_state)

        # Construieste contextul pentru LLM
        history_text = ""
        if self.history:
            recent = self.history[-5:]
            history_text = "Ultimele actiuni executate:\n" + "\n".join(
                [f"- {h['action']}: {h.get('reason', '')} (rezultat: {h.get('result', 'necunoscut')})"
                 for h in recent]
            )

        prompt = f"""
Joc: {game_name}
Starea curenta:
{json.dumps(game_state, indent=2, ensure_ascii=False)}

{history_text}

Strategii si cunostinte relevante:
{knowledge if knowledge else "Nu exista cunostinte specifice inca. Joaca intuitiv bazat pe ce vezi."}

Analizeaza screenshot-ul si starea jocului. Decide urmatoarea actiune optima.
Returneaza EXCLUSIV un JSON valid:
{{
  "action": "click|drag|key|wait|reroll|buy|sell|place|combine",
  "x": <int sau null>,
  "y": <int sau null>,
  "from_x": <int sau null>,
  "from_y": <int sau null>,
  "key": <"enter"|"space"|"esc" sau null>,
  "target_description": "<ce element UI>,
  "reason": "<de ce aceasta actiune>",
  "confidence": <0.0-1.0>,
  "priority": <1-10>
}}
"""
        log.debug("Solicit decizie de la LLM...")

        try:
            message = self.client.messages.create(
                model=self.model,
                max_tokens=512,
                system=DECISION_SYSTEM_PROMPT,
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image",
                                "source": {
                                    "type": "base64",
                                    "media_type": "image/jpeg",
                                    "data": screenshot_b64,
                                },
                            },
                            {"type": "text", "text": prompt},
                        ],
                    }
                ],
            )

            response_text = message.content[0].text
            log.debug(f"Decizie LLM bruta: {response_text}")

            # Parse JSON din raspuns
            action = self._parse_json_response(response_text)

            # Adauga la istoric
            self.history.append(action)
            if len(self.history) > self.max_history:
                self.history.pop(0)

            return action

        except Exception as e:
            log.error(f"Eroare la decizie LLM: {e}")
            return {"action": "wait", "reason": f"Eroare: {e}", "confidence": 0.0}

    def _parse_json_response(self, text: str) -> Dict[str, Any]:
        """Extrage JSON din raspunsul LLM (chiar daca are text extra)."""
        # Incearca sa gaseasca JSON in text
        json_match = re.search(r'\{.*\}', text, re.DOTALL)
        if json_match:
            try:
                return json.loads(json_match.group())
            except json.JSONDecodeError:
                pass

        # Fallback daca nu gaseste JSON valid
        log.warning("Nu s-a putut parsa JSON din raspuns. Asteapta.")
        return {
            "action": "wait",
            "reason": "JSON invalid in raspunsul LLM",
            "confidence": 0.0,
            "priority": 1,
        }

    def mark_action_result(self, action: Dict, success: bool, notes: str = ""):
        """Marcheaza rezultatul ultimei actiuni pentru invatare."""
        if self.history:
            self.history[-1]["result"] = "succes" if success else "esec"
            self.history[-1]["notes"] = notes

    def analyze_and_learn(self, game_state: Dict, action: Dict, outcome: str):
        """Extrage lectii din experienta si le salveaza in knowledge base."""
        if action.get("confidence", 0) > 0.7 and "succes" in outcome:
            self.knowledge_base.add_experience(
                game_name=game_state.get("game", "unknown"),
                situation=game_state,
                action=action,
                outcome=outcome,
            )
