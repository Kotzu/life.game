"""
Knowledge Base - versiune standalone pentru Juno/iPhone.
Salveaza strategii si experiente intr-un fisier JSON local.
Calea implicita e in sandbox-ul Juno (Documents/).
"""

import json
import os
from datetime import datetime
from typing import Any, Dict, List


class KnowledgeBase:
    def __init__(self, path: str = "knowledge_base.json"):
        # In Juno, fisierele se salveaza in directorul notebook-ului
        self.path = path
        self.data = self._load()

    def _load(self) -> dict:
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {
            "strategies": {},
            "youtube_knowledge": {},
            "experiences": {},
            "meta": {"version": "1.0", "created": datetime.now().isoformat()},
        }

    def save(self):
        with open(self.path, "w", encoding="utf-8") as f:
            json.dump(self.data, f, indent=2, ensure_ascii=False)

    def add_youtube_knowledge(self, game: str, text: str, source: str = ""):
        self.data["youtube_knowledge"].setdefault(game, []).append({
            "text": text, "source": source,
            "added": datetime.now().isoformat(),
        })
        self.save()
        print(f"✅ Salvat {len(text)} caractere de strategii pentru '{game}'")

    def add_strategy(self, game: str, text: str):
        self.data["strategies"].setdefault(game, []).append({
            "text": text, "added": datetime.now().isoformat(),
        })
        self.save()

    def get_all_knowledge(self, game: str) -> str:
        parts = []
        for item in self.data["youtube_knowledge"].get(game, []):
            parts.append(item["text"])
        for item in self.data["strategies"].get(game, []):
            parts.append(f"• {item['text']}")
        return "\n\n".join(parts)

    def stats(self) -> dict:
        return {
            "jocuri": list(set(
                list(self.data["youtube_knowledge"].keys()) +
                list(self.data["strategies"].keys())
            )),
            "surse_youtube": sum(len(v) for v in self.data["youtube_knowledge"].values()),
            "strategii": sum(len(v) for v in self.data["strategies"].values()),
        }

    def show_stats(self):
        s = self.stats()
        print(f"📚 Knowledge Base:")
        print(f"   Jocuri:         {', '.join(s['jocuri']) or 'niciunul'}")
        print(f"   Surse YouTube:  {s['surse_youtube']}")
        print(f"   Strategii:      {s['strategii']}")
