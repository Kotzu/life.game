"""
Base Game - Clasa de baza pentru orice joc.
Toate jocurile suportate trebuie sa extinda aceasta clasa.
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, Optional


class BaseGame(ABC):
    """
    Interfata de baza pentru module de jocuri.
    Implementeaza aceasta clasa pentru fiecare joc nou.
    """

    def __init__(self, config: dict, screen_capture, input_controller, vision_analyzer):
        self.config = config
        self.screen = screen_capture
        self.input = input_controller
        self.vision = vision_analyzer
        self.screen_w, self.screen_h = screen_capture.get_screen_size()

    @property
    @abstractmethod
    def game_name(self) -> str:
        """Returneaza numele jocului."""
        pass

    @abstractmethod
    def parse_game_state(self, screenshot_b64: str) -> Dict[str, Any]:
        """
        Extrage starea jocului din screenshot.
        Returns dict cu info relevante (gold, hp, unitati, etc.)
        """
        pass

    @abstractmethod
    def execute_action(self, action: Dict[str, Any]) -> bool:
        """
        Executa o actiune in joc.
        Returns True daca actiunea a reusit.
        """
        pass

    @abstractmethod
    def is_game_active(self, screenshot_b64: str) -> bool:
        """Verifica daca jocul e activ/in desfasurare."""
        pass

    def get_system_prompt(self) -> str:
        """Returneaza system prompt-ul specific jocului pentru LLM."""
        return f"Esti un expert in {self.game_name}. Joaca optimal."

    def _pct_to_px(self, x_pct: float, y_pct: float):
        """Converteste procente in pixeli absoluti."""
        return int(x_pct * self.screen_w), int(y_pct * self.screen_h)
