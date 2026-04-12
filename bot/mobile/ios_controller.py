"""
iOS Controller - Controleaza iPhone-ul pentru bot.

Screenshot: via pymobiledevice3 (USB) SAU via WDA (WiFi/USB tunnel)
Touch:      via WebDriverAgent (WDA) HTTP API

Setup necesar (o singura data):
  1. iPhone: Settings > Privacy & Security > Developer Mode -> ON
  2. PC: pip install tidevice pymobiledevice3
  3. Conecteaza iPhone la PC via USB
  4. Ruleaza pe PC (intr-un terminal separat):
       tidevice xctest --bundle_id com.facebook.WebDriverAgentRunner
  5. Botul se conecteaza automat la WDA pe portul 8100

Alternativa fara USB (AirPlay):
  - Oglindeste ecranul iPhone via QuickTime (Mac) sau AirServer (PC/Mac)
  - Botul capteaza ecranul oglindit cu MSS (mod desktop)
  - Touch-urile se trimit tot via WDA (WiFi)
"""

import base64
import io
import subprocess
import threading
import time
from typing import Optional, Tuple

from PIL import Image

from mobile.wda_client import WDAClient
from utils.logger import log


class iOSController:
    """
    Controller complet pentru iPhone: screenshot + touch.
    Doua moduri de captura: USB direct (pymobiledevice3) sau WDA.
    """

    def __init__(self, config: dict):
        mobile_cfg = config.get("mobile", {})
        self.wda_host = mobile_cfg.get("wda_host", "localhost")
        self.wda_port = mobile_cfg.get("wda_port", 8100)
        self.screenshot_mode = mobile_cfg.get("screenshot_mode", "wda")  # "wda" | "usb"
        self.scale_factor = mobile_cfg.get("scale_factor", 1.0)

        # WDA client (touch + screenshot fallback)
        self.wda = WDAClient(self.wda_host, self.wda_port)

        # Screen size cache
        self._screen_w = None
        self._screen_h = None

        log.info(f"iOSController initializat | WDA: {self.wda_host}:{self.wda_port}")

    def connect(self) -> bool:
        """Conecteaza la WDA si verifica conexiunea."""
        if not self.wda.ping():
            log.error(
                f"WDA nu raspunde la {self.wda_host}:{self.wda_port}!\n"
                "Asigura-te ca rulezi:\n"
                "  tidevice xctest --bundle_id com.facebook.WebDriverAgentRunner\n"
                "sau\n"
                "  iproxy 8100 8100 &   # pentru USB tunnel"
            )
            return False

        if not self.wda.create_session():
            log.error("Nu s-a putut crea sesiunea WDA.")
            return False

        # Cache screen size
        self._screen_w, self._screen_h = self.wda.get_screen_size()
        log.info(f"iPhone conectat: {self._screen_w}x{self._screen_h} puncte")
        return True

    def get_screen_size(self) -> Tuple[int, int]:
        if self._screen_w:
            return self._screen_w, self._screen_h
        return self.wda.get_screen_size()

    # ===== SCREENSHOT =====

    def capture(self) -> Optional[Image.Image]:
        """Captureaza ecranul iPhone."""
        if self.screenshot_mode == "usb":
            return self._capture_usb()
        return self._capture_wda()

    def _capture_wda(self) -> Optional[Image.Image]:
        """Screenshot via WDA (WiFi sau USB tunnel)."""
        b64 = self.wda.get_screenshot_b64()
        if b64:
            img_data = base64.b64decode(b64)
            return Image.open(io.BytesIO(img_data)).convert("RGB")
        return None

    def _capture_usb(self) -> Optional[Image.Image]:
        """Screenshot via pymobiledevice3 (USB direct, mai rapid)."""
        try:
            from pymobiledevice3.lockdown import LockdownClient
            from pymobiledevice3.services.screenshot import ScreenshotService

            lockdown = LockdownClient()
            with ScreenshotService(lockdown) as screenshot_svc:
                png_data = screenshot_svc.take_screenshot()
                return Image.open(io.BytesIO(png_data)).convert("RGB")
        except ImportError:
            log.warning("pymobiledevice3 nu e instalat. Folosesc WDA pentru screenshot.")
            return self._capture_wda()
        except Exception as e:
            log.warning(f"USB screenshot eroare: {e}. Fallback WDA.")
            return self._capture_wda()

    def capture_to_base64(self, max_width: int = 1024) -> Optional[str]:
        """Captureaza si comprima pentru API LLM."""
        img = self.capture()
        if img is None:
            return None

        # Resize daca necesar
        if img.width > max_width:
            ratio = max_width / img.width
            img = img.resize((max_width, int(img.height * ratio)), Image.LANCZOS)

        buffer = io.BytesIO()
        img.save(buffer, format="JPEG", quality=85)
        return base64.b64encode(buffer.getvalue()).decode("utf-8")

    # ===== TOUCH / INPUT =====

    def tap(self, x: int, y: int) -> bool:
        """Tap la coordonate absolute (in puncte iPhone)."""
        log.debug(f"iOS tap: ({x}, {y})")
        return self.wda.tap(x, y)

    def tap_pct(self, x_pct: float, y_pct: float) -> bool:
        """Tap la coordonate procentuale (0.0-1.0)."""
        w, h = self.get_screen_size()
        return self.tap(int(x_pct * w), int(y_pct * h))

    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, duration: float = 0.4) -> bool:
        """Swipe/drag de la un punct la altul."""
        log.debug(f"iOS swipe: ({from_x},{from_y}) -> ({to_x},{to_y})")
        return self.wda.swipe(from_x, from_y, to_x, to_y, duration)

    def swipe_pct(self, fx: float, fy: float, tx: float, ty: float) -> bool:
        """Swipe cu coordonate procentuale."""
        w, h = self.get_screen_size()
        return self.swipe(int(fx * w), int(fy * h), int(tx * w), int(ty * h))

    def long_press(self, x: int, y: int, duration: float = 1.0) -> bool:
        """Long press."""
        return self.wda.press_and_hold(x, y, duration)

    def double_tap(self, x: int, y: int) -> bool:
        """Double tap."""
        return self.wda.double_tap(x, y)

    def close(self):
        """Inchide conexiunea WDA."""
        self.wda.close_session()
        log.info("iOSController inchis.")

    # ===== UTILS =====

    def start_wda_tunnel(self) -> subprocess.Popen:
        """
        Porneste automat tunelul USB pentru WDA (iproxy).
        Returneaza procesul pentru a-l putea opri mai tarziu.
        """
        log.info("Pornesc tunel USB pentru WDA (iproxy 8100 8100)...")
        proc = subprocess.Popen(
            ["iproxy", "8100", "8100"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        time.sleep(1)
        return proc

    def wait_for_wda(self, timeout: int = 30) -> bool:
        """Asteapta pana cand WDA e disponibil (max timeout secunde)."""
        log.info(f"Astept WDA... (max {timeout}s)")
        start = time.time()
        while time.time() - start < timeout:
            if self.wda.ping():
                log.info("WDA e disponibil!")
                return True
            time.sleep(2)
        log.error(f"WDA nu a raspuns in {timeout} secunde.")
        return False
