"""
Vision Analyzer - Un singur apel Claude per ciclu.
Analizeaza screenshot-ul, extrage starea si decide actiunea simultan.
"""

import json
import os
import re
from typing import Any, Dict

import anthropic

from utils.logger import log


ONE_SHOT_PROMPT = """Esti un bot expert la Dota Underlords. Analizezi un screenshot si returnezi un JSON cu:
1. Ce ecran este vizibil
2. Starea jocului (daca esti in joc)
3. Actiunea optima de facut ACUM

COORDONATE: intotdeauna ca procente 0.0-1.0 (x_pct=0.0 stanga, 1.0 dreapta; y_pct=0.0 sus, 1.0 jos)

Raspunde EXCLUSIV cu JSON valid:
{
  "screen": "main_menu|mode_select|loading|in_game|game_over|unknown",
  "gold": <int sau null>,
  "hp": <int sau null>,
  "round": <int sau null>,
  "phase": "planning|combat|shopping|unknown",
  "action": "click|wait|key",
  "x_pct": <0.0-1.0 sau null>,
  "y_pct": <0.0-1.0 sau null>,
  "target": "<ce apesi>",
  "reason": "<de ce>",
  "confidence": <0.0-1.0>
}"""


class VisionAnalyzer:
    def __init__(self, config: dict):
        api_key = os.environ.get(config["ai"]["api_key_env"])
        if not api_key:
            raise ValueError(f"API key lipsa. Seteaza {config['ai']['api_key_env']}")

        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = config["ai"]["vision_model"]
        self.max_tokens = config["ai"]["max_tokens"]
        log.info(f"VisionAnalyzer: {self.model}")

    def analyze_and_decide(
        self,
        screenshot_b64: str,
        history: str = "",
        knowledge: str = "",
    ) -> Dict[str, Any]:
        """
        UN singur apel API: vede ecranul, extrage starea, decide actiunea.
        Inlocuieste 3-4 apeluri separate.
        """
        context = ""
        if history:
            context += f"\nUltimele actiuni (cu rezultat):\n{history}"
        if knowledge:
            context += f"\nStrategii cunoscute:\n{knowledge[:500]}"
        if context:
            context = f"\nCONTEXT:{context}"

        try:
            msg = self.client.messages.create(
                model=self.model,
                max_tokens=512,
                system=ONE_SHOT_PROMPT,
                messages=[{
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
                        {
                            "type": "text",
                            "text": f"Analizeaza si decide urmatoarea actiune.{context}",
                        },
                    ],
                }],
            )

            raw = msg.content[0].text
            log.debug(f"Vision raw: {raw[:200]}")
            return self._parse(raw)

        except Exception as e:
            log.error(f"VisionAnalyzer eroare: {e}")
            return {"screen": "unknown", "action": "wait", "reason": str(e), "confidence": 0.0}

    def _parse(self, text: str) -> Dict[str, Any]:
        m = re.search(r'\{.*\}', text, re.DOTALL)
        if m:
            try:
                return json.loads(m.group())
            except json.JSONDecodeError:
                pass
        return {"screen": "unknown", "action": "wait", "reason": "parse error", "confidence": 0.0}

    # Pastrat pentru compatibilitate cu cod vechi
    def describe_scene(self, screenshot_b64: str) -> str:
        result = self.analyze_and_decide(screenshot_b64)
        return f"screen={result.get('screen')} phase={result.get('phase')} target={result.get('target')}"
