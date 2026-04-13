"""Config loader - incarca settings.yaml."""

import os
from pathlib import Path

import yaml


def load_config(config_path: str = None) -> dict:
    """Incarca configuratia din YAML."""
    if config_path is None:
        # Cauta config relativ la directorul botului
        bot_dir = Path(__file__).parent.parent
        config_path = bot_dir / "config" / "settings.yaml"

    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)
