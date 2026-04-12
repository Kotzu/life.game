"""
Vision Analyzer - Foloseste Claude Vision API pentru analiza screenshots.
Trimite imagini la Claude si interpreteaza starea jocului.
"""

import os
from typing import Any, Dict, Optional

import anthropic

from utils.logger import log


class VisionAnalyzer:
    """
    Analizator vizual bazat pe Claude Vision.
    Interpreteaza screenshots ale jocului si extrage informatii structurate.
    """

    def __init__(self, config: dict):
        api_key = os.environ.get(config["ai"]["api_key_env"])
        if not api_key:
            raise ValueError(
                f"API key nu a fost gasit. Seteaza variabila {config['ai']['api_key_env']}"
            )

        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = config["ai"]["vision_model"]
        self.max_tokens = config["ai"]["max_tokens"]

        log.info(f"VisionAnalyzer initializat cu modelul {self.model}")

    def analyze_game_state(
        self,
        screenshot_b64: str,
        game_context: str,
        system_prompt: str,
    ) -> Dict[str, Any]:
        """
        Analizeza un screenshot al jocului si returneaza starea parsed.

        Args:
            screenshot_b64: Screenshot encodat in base64
            game_context: Context specific jocului (ce sa caute)
            system_prompt: Instructiunile de sistem pentru AI

        Returns:
            Dict cu starea jocului extrasa
        """
        log.debug("Trimit screenshot la Claude Vision pentru analiza...")

        message = self.client.messages.create(
            model=self.model,
            max_tokens=self.max_tokens,
            system=system_prompt,
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
                        {
                            "type": "text",
                            "text": game_context,
                        },
                    ],
                }
            ],
        )

        response_text = message.content[0].text
        log.debug(f"Raspuns Claude Vision: {response_text[:200]}...")

        return {"raw_response": response_text, "usage": message.usage}

    def decide_action(
        self,
        screenshot_b64: str,
        game_state: Dict[str, Any],
        knowledge: str,
        system_prompt: str,
    ) -> str:
        """
        Pe baza starii jocului si cunostintelor, decide urmatoarea actiune.

        Args:
            screenshot_b64: Screenshot curent
            game_state: Starea jocului extrasa anterior
            knowledge: Cunostinte invatate din YouTube/experienta
            system_prompt: Instructiuni de sistem

        Returns:
            JSON string cu actiunile de executat
        """
        log.debug("Solicit decizie de la Claude...")

        user_message = f"""
Starea curenta a jocului:
{game_state}

Cunostinte si strategii invatate:
{knowledge}

Pe baza screenshot-ului si starii jocului, decide cea mai buna actiune urmatoare.
Returneaza DOAR un JSON valid cu structura:
{{
  "action": "click|drag|key|wait|reroll|buy|sell|place|combine",
  "target": "descriere sau coordonate",
  "x": null,
  "y": null,
  "reason": "explicatie scurta",
  "confidence": 0.0-1.0
}}
"""
        message = self.client.messages.create(
            model=self.model,
            max_tokens=512,
            system=system_prompt,
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
                        {"type": "text", "text": user_message},
                    ],
                }
            ],
        )

        return message.content[0].text

    def describe_scene(self, screenshot_b64: str) -> str:
        """Descrie generic ce vede in screenshot (pentru debugging/learning)."""
        message = self.client.messages.create(
            model=self.model,
            max_tokens=1024,
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
                        {
                            "type": "text",
                            "text": "Descrie detaliat ce vezi in aceasta imagine. Daca e un joc, identifica UI elements, starea jocului, resurse, unitati, etc.",
                        },
                    ],
                }
            ],
        )
        return message.content[0].text
