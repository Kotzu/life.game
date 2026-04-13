"""
Input Controller - Low-level mouse/keyboard via pynput.
Foloseste OS-level APIs (evdev pe Linux, Win32 pe Windows).
Miscare bezier pentru mouse (apare uman, timing randomizat).
"""

import math
import platform
import random
import subprocess
import time
from typing import List, Optional, Tuple

from pynput.keyboard import Controller as KeyboardController
from pynput.keyboard import Key
from pynput.mouse import Button
from pynput.mouse import Controller as MouseController

from utils.logger import log


def _bezier(p0, p1, p2, p3, t):
    """Punct pe curba bezier cubica."""
    return (
        (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t ** 2 * p2[0] + t ** 3 * p3[0],
        (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t ** 2 * p2[1] + t ** 3 * p3[1],
    )


class InputController:
    """
    Controleaza mouse si tastatura cu miscare umana.
    Toate timpii sunt randomizati in interval pentru a evita pattern-uri fixe.
    """

    def __init__(self, config: dict):
        self.mouse = MouseController()
        self.keyboard = KeyboardController()
        self.cfg = config.get("input", {})

        # Parametri din config cu fallback-uri sigure
        self.click_delay = (
            self.cfg.get("click_delay_min", 0.08),
            self.cfg.get("click_delay_max", 0.25),
        )
        self.move_duration = (
            self.cfg.get("move_duration_min", 0.1),
            self.cfg.get("move_duration_max", 0.4),
        )
        self.action_pause = (
            self.cfg.get("action_pause_min", 0.3),
            self.cfg.get("action_pause_max", 1.2),
        )
        self.bezier_dev = self.cfg.get("bezier_deviation", 30)

        log.debug("InputController initializat cu miscare umana")

    def _rand_sleep(self, min_s: float, max_s: float):
        """Sleep randomizat intre min si max secunde."""
        time.sleep(random.uniform(min_s, max_s))

    def _human_move(self, target_x: int, target_y: int):
        """
        Muta mouse-ul pe o curba bezier (miscare umana).
        Adauga deviatie aleatorie in punctele de control.
        """
        start = self.mouse.position
        end = (target_x, target_y)

        # Puncte de control bezier (cu zgomot uman)
        dev = self.bezier_dev
        cp1 = (
            start[0] + random.randint(-dev, dev) + (end[0] - start[0]) * 0.3,
            start[1] + random.randint(-dev, dev) + (end[1] - start[1]) * 0.3,
        )
        cp2 = (
            start[0] + random.randint(-dev, dev) + (end[0] - start[0]) * 0.7,
            start[1] + random.randint(-dev, dev) + (end[1] - start[1]) * 0.7,
        )

        duration = random.uniform(*self.move_duration)
        steps = max(20, int(duration * 60))  # ~60fps movement

        for i in range(steps + 1):
            t = i / steps
            # Ease in-out (mai natural)
            t_ease = t * t * (3 - 2 * t)
            pos = _bezier(start, cp1, cp2, end, t_ease)
            self.mouse.position = (int(pos[0]), int(pos[1]))
            time.sleep(duration / steps)

    def move_to(self, x: int, y: int):
        """Muta mouse-ul la coordonate absolute."""
        log.debug(f"Mouse move -> ({x}, {y})")
        self._human_move(x, y)

    def move_to_pct(self, x_pct: float, y_pct: float, screen_w: int, screen_h: int):
        """Muta mouse-ul la coordonate procentuale (0.0-1.0)."""
        x = int(x_pct * screen_w)
        y = int(y_pct * screen_h)
        self.move_to(x, y)

    def _focus_game(self):
        """Aduce fereastra jocului in prim-plan pe macOS."""
        if platform.system() == "Darwin":
            for app in ("Dota Underlords", "dota_underlords"):
                try:
                    subprocess.run(
                        ["osascript", "-e", f'tell application "{app}" to activate'],
                        capture_output=True, timeout=2
                    )
                    time.sleep(0.1)
                    break
                except Exception:
                    pass

    def click(self, x: Optional[int] = None, y: Optional[int] = None, button: str = "left"):
        """Click (cu miscare umana daca sunt specificate coordonate)."""
        if x is not None and y is not None:
            self.move_to(x, y)

        btn = Button.left if button == "left" else Button.right
        self._rand_sleep(*self.click_delay)
        self.mouse.click(btn)
        log.debug(f"Click {button} la {self.mouse.position}")

    def double_click(self, x: Optional[int] = None, y: Optional[int] = None):
        """Double click."""
        if x is not None and y is not None:
            self.move_to(x, y)
        self._rand_sleep(*self.click_delay)
        self.mouse.click(Button.left, 2)
        log.debug(f"Double click la {self.mouse.position}")

    def drag(self, from_x: int, from_y: int, to_x: int, to_y: int):
        """Drag and drop (tinand butonul apasat)."""
        self.move_to(from_x, from_y)
        self._rand_sleep(0.1, 0.2)
        self.mouse.press(Button.left)
        self._rand_sleep(0.05, 0.15)
        self._human_move(to_x, to_y)
        self._rand_sleep(0.05, 0.1)
        self.mouse.release(Button.left)
        log.debug(f"Drag ({from_x},{from_y}) -> ({to_x},{to_y})")

    def press_key(self, key: str):
        """Apasa o tasta (suporta caractere si taste speciale)."""
        self._rand_sleep(0.05, 0.15)
        if len(key) == 1:
            self.keyboard.press(key)
            time.sleep(random.uniform(0.05, 0.1))
            self.keyboard.release(key)
        else:
            special_keys = {
                "enter": Key.enter,
                "space": Key.space,
                "esc": Key.esc,
                "tab": Key.tab,
                "f1": Key.f1,
                "f2": Key.f2,
            }
            k = special_keys.get(key.lower(), key)
            self.keyboard.press(k)
            time.sleep(random.uniform(0.05, 0.1))
            self.keyboard.release(k)
        log.debug(f"Key press: {key}")

    def pause(self):
        """Pauza umana intre actiuni."""
        self._rand_sleep(*self.action_pause)

    def scroll(self, x: int, y: int, clicks: int):
        """Scroll la pozitia specificata."""
        self.move_to(x, y)
        self._rand_sleep(0.1, 0.2)
        self.mouse.scroll(0, clicks)
