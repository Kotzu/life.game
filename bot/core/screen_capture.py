"""
Screen capture module - stealthy, low-level, uses MSS.
MSS foloseste DirectX/X11 direct, aproape imposibil de detectat.
"""

import base64
import io
import time
from typing import Optional, Tuple

import mss
import mss.tools
import numpy as np
from PIL import Image

from utils.logger import log


class ScreenCapture:
    """Captureaza ecranul folosind MSS (low-level, stealthy)."""

    def __init__(self, monitor_index: int = 0):
        self.monitor_index = monitor_index
        self._sct = None
        self._monitor = None

    def _get_sct(self):
        """Lazy init MSS context (thread safe)."""
        if self._sct is None:
            self._sct = mss.mss()
            monitors = self._sct.monitors
            # monitors[0] = all monitors combined, monitors[1+] = individual
            self._monitor = monitors[self.monitor_index + 1] if len(monitors) > 1 else monitors[0]
            log.debug(f"Screen capture init: {self._monitor['width']}x{self._monitor['height']}")
        return self._sct, self._monitor

    def capture(self, region: Optional[Tuple[float, float, float, float]] = None) -> Image.Image:
        """
        Captureaza ecranul sau o regiune.

        Args:
            region: (x1%, y1%, x2%, y2%) - coordonate in procente din ecran
                    Exemplu: (0.0, 0.0, 1.0, 1.0) = ecran complet
        Returns:
            PIL Image
        """
        sct, monitor = self._get_sct()

        if region is None:
            # Full screen capture
            screenshot = sct.grab(monitor)
        else:
            # Region capture (calculeaza pixeli absoluti)
            x1 = int(monitor["left"] + region[0] * monitor["width"])
            y1 = int(monitor["top"] + region[1] * monitor["height"])
            x2 = int(monitor["left"] + region[2] * monitor["width"])
            y2 = int(monitor["top"] + region[3] * monitor["height"])

            capture_region = {
                "left": x1,
                "top": y1,
                "width": x2 - x1,
                "height": y2 - y1,
            }
            screenshot = sct.grab(capture_region)

        # Converteste BGRA -> RGB
        img = Image.frombytes("RGB", screenshot.size, screenshot.bgra, "raw", "BGRX")
        return img

    def capture_to_numpy(self, region=None) -> np.ndarray:
        """Captureaza si returneaza numpy array (BGR pentru OpenCV)."""
        img = self.capture(region)
        return np.array(img)[:, :, ::-1]  # RGB -> BGR

    def capture_to_base64(self, region=None, max_width: int = 1280) -> str:
        """
        Captureaza si comprima pentru trimitere la API LLM.
        Resize-uieste daca e prea mare (economie API tokens).
        """
        img = self.capture(region)

        # Resize daca necesar (LLM nu are nevoie de full HD pentru decizii)
        if img.width > max_width:
            ratio = max_width / img.width
            new_h = int(img.height * ratio)
            img = img.resize((max_width, new_h), Image.LANCZOS)

        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=85)
        return base64.b64encode(buffer.getvalue()).decode("utf-8")

    def get_screen_size(self) -> Tuple[int, int]:
        """Returneaza dimensiunea ecranului (width, height)."""
        _, monitor = self._get_sct()
        return monitor["width"], monitor["height"]

    def save_screenshot(self, path: str, region=None):
        """Salveaza screenshot pentru debug."""
        img = self.capture(region)
        img.save(path)
        log.debug(f"Screenshot salvat: {path}")

    def fingerprint(self) -> int:
        """
        Hash rapid al ecranului pentru a detecta daca s-a schimbat ceva.
        Esantioneaza 200 de pixeli distribuiti uniform — rapid si suficient de sensibil.
        """
        img = self.capture()
        w, h = img.size
        pixels = img.load()
        sample = 0
        step_x = max(1, w // 20)
        step_y = max(1, h // 10)
        for x in range(0, w, step_x):
            for y in range(0, h, step_y):
                r, g, b = pixels[x, y]
                sample = (sample * 31 + r * 3 + g * 5 + b * 7) & 0xFFFFFFFF
        return sample

    def close(self):
        if self._sct:
            self._sct.close()
            self._sct = None
