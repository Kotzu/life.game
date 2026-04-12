"""
Knowledge Base - Stocheaza si retriveaza cunostinte invatate.
Combina strategii din YouTube cu experienta acumulata in-game.
"""

import json
import os
from datetime import datetime
from typing import Any, Dict, List, Optional

from utils.logger import log


class KnowledgeBase:
    """
    Baza de cunostinte persistenta pentru bot.
    Stocheaza strategii, tipare de joc si lectii invatate.
    """

    def __init__(self, path: str = "data/knowledge_base.json"):
        self.path = path
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.data = self._load()
        log.info(f"KnowledgeBase incarcata: {len(self.data.get('strategies', {}))} jocuri")

    def _load(self) -> Dict:
        """Incarca baza de date din fisier."""
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                log.warning(f"Eroare la incarcare KB: {e}. Pornesc fresh.")
        return {
            "strategies": {},      # {game: [strategie1, strategie2, ...]}
            "experiences": {},     # {game: [experienta1, ...]}
            "youtube_knowledge": {},  # {game: text extras din YouTube}
            "meta": {
                "version": "1.0",
                "created": datetime.now().isoformat(),
            }
        }

    def save(self):
        """Salveaza baza de date pe disk."""
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=2, ensure_ascii=False)
        log.debug("KnowledgeBase salvata.")

    def add_youtube_knowledge(self, game_name: str, knowledge_text: str, source_url: str = ""):
        """Adauga cunostinte extrase din YouTube."""
        if game_name not in self.data["youtube_knowledge"]:
            self.data["youtube_knowledge"][game_name] = []

        self.data["youtube_knowledge"][game_name].append({
            "text": knowledge_text,
            "source": source_url,
            "added": datetime.now().isoformat(),
        })
        self.save()
        log.info(f"Adaugata cunostinta YouTube pentru {game_name} ({len(knowledge_text)} chars)")

    def add_strategy(self, game_name: str, strategy: str, tags: List[str] = None):
        """Adauga o strategie manuala sau extrasa."""
        if game_name not in self.data["strategies"]:
            self.data["strategies"][game_name] = []

        self.data["strategies"][game_name].append({
            "text": strategy,
            "tags": tags or [],
            "added": datetime.now().isoformat(),
            "uses": 0,
        })
        self.save()

    def add_experience(self, game_name: str, situation: Dict, action: Dict, outcome: str):
        """Adauga o experienta de joc (situatie + actiune + rezultat)."""
        if game_name not in self.data["experiences"]:
            self.data["experiences"][game_name] = []

        self.data["experiences"][game_name].append({
            "situation_summary": self._summarize_situation(situation),
            "action": action.get("action"),
            "action_reason": action.get("reason"),
            "outcome": outcome,
            "timestamp": datetime.now().isoformat(),
        })

        # Pastreaza doar ultimele 100 de experiente per joc
        if len(self.data["experiences"][game_name]) > 100:
            self.data["experiences"][game_name] = self.data["experiences"][game_name][-100:]

        self.save()

    def get_relevant_knowledge(self, game_name: str, game_state: Dict) -> str:
        """
        Returneaza cunostintele relevante pentru situatia curenta.
        Combina strategii YouTube + experiente anterioare.
        """
        parts = []

        # Strategii YouTube
        yt_knowledge = self.data["youtube_knowledge"].get(game_name, [])
        if yt_knowledge:
            parts.append("=== Strategii invatate din YouTube ===")
            for item in yt_knowledge[-3:]:  # Ultimele 3 adaugiri
                parts.append(item["text"][:1000])  # Limita 1000 chars per item

        # Strategii manuale
        strategies = self.data["strategies"].get(game_name, [])
        if strategies:
            parts.append("\n=== Strategii cunoscute ===")
            for s in strategies[:5]:
                parts.append(f"- {s['text']}")

        # Experiente relevante
        experiences = self.data["experiences"].get(game_name, [])
        if experiences:
            successful = [e for e in experiences if "succes" in e.get("outcome", "").lower()]
            if successful:
                parts.append("\n=== Actiuni de succes anterioare ===")
                for e in successful[-5:]:
                    parts.append(f"- Situatie: {e['situation_summary']} -> Actiune: {e['action']} ({e['action_reason']})")

        return "\n".join(parts) if parts else ""

    def _summarize_situation(self, situation: Dict) -> str:
        """Rezuma starea jocului intr-un string scurt."""
        relevant = {
            k: v for k, v in situation.items()
            if k in ["gold", "hp", "round", "level", "units", "shop"]
        }
        return json.dumps(relevant, ensure_ascii=False)[:200]

    def list_games(self) -> List[str]:
        """Lista jocurilor cu cunostinte stocate."""
        all_games = set()
        all_games.update(self.data["strategies"].keys())
        all_games.update(self.data["youtube_knowledge"].keys())
        return list(all_games)

    def get_stats(self) -> Dict:
        """Statistici despre baza de cunostinte."""
        return {
            "games": self.list_games(),
            "total_strategies": sum(len(v) for v in self.data["strategies"].values()),
            "total_experiences": sum(len(v) for v in self.data["experiences"].values()),
            "youtube_sources": sum(len(v) for v in self.data["youtube_knowledge"].values()),
        }
