"""
WebDriverAgent (WDA) client - trimite touch events la iPhone via HTTP.

WDA e un framework open-source de la Facebook care expune un server HTTP
pe iPhone. Botul trimite request-uri HTTP pentru tap, swipe, drag etc.

Setup (o singura data pe iPhone):
  1. Activeaza Developer Mode: Settings -> Privacy & Security -> Developer Mode
  2. Conecteaza iPhone la PC via USB
  3. Ruleaza: tidevice xctest --bundle_id com.facebook.WebDriverAgentRunner
  4. WDA porneste pe portul 8100 (sau forwarded via USB tunnel)

Documentatie WDA: https://github.com/appium/WebDriverAgent
"""

import time
from typing import Optional, Tuple

import requests

from utils.logger import log


class WDAClient:
    """
    Client HTTP pentru WebDriverAgent.
    Controleaza touch-urile pe iPhone via REST API.
    """

    def __init__(self, host: str = "localhost", port: int = 8100):
        self.base_url = f"http://{host}:{port}"
        self.session_id: Optional[str] = None
        self.timeout = 10

    def ping(self) -> bool:
        """Verifica daca WDA ruleaza."""
        try:
            r = requests.get(f"{self.base_url}/status", timeout=3)
            return r.status_code == 200
        except Exception:
            return False

    def create_session(self) -> bool:
        """Creeaza sesiune WDA (necesara inainte de orice actiune)."""
        try:
            payload = {
                "capabilities": {
                    "firstMatch": [{}],
                    "alwaysMatch": {
                        "platformName": "iOS",
                    }
                }
            }
            r = requests.post(
                f"{self.base_url}/session",
                json=payload,
                timeout=self.timeout
            )
            if r.status_code in (200, 201):
                data = r.json()
                self.session_id = data.get("sessionId") or data.get("value", {}).get("sessionId")
                log.info(f"WDA sesiune creata: {self.session_id}")
                return True
            log.error(f"WDA session error: {r.status_code} {r.text[:200]}")
            return False
        except Exception as e:
            log.error(f"WDA create_session error: {e}")
            return False

    def ensure_session(self) -> bool:
        """Asigura ca exista o sesiune activa."""
        if self.session_id:
            return True
        return self.create_session()

    def tap(self, x: int, y: int) -> bool:
        """Tap simplu la coordonate (x, y) in pixeli."""
        if not self.ensure_session():
            return False
        try:
            payload = {"x": x, "y": y}
            r = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/tap/0",
                json=payload,
                timeout=self.timeout
            )
            success = r.status_code in (200, 204)
            log.debug(f"WDA tap ({x},{y}): {'OK' if success else r.status_code}")
            return success
        except Exception as e:
            log.error(f"WDA tap error: {e}")
            return False

    def double_tap(self, x: int, y: int) -> bool:
        """Double tap la coordonate."""
        self.tap(x, y)
        time.sleep(0.1)
        return self.tap(x, y)

    def press_and_hold(self, x: int, y: int, duration: float = 1.0) -> bool:
        """Long press la coordonate (duration in secunde)."""
        if not self.ensure_session():
            return False
        try:
            payload = {
                "actions": [{
                    "type": "pointer",
                    "id": "finger1",
                    "parameters": {"pointerType": "touch"},
                    "actions": [
                        {"type": "pointerMove", "duration": 0, "x": x, "y": y},
                        {"type": "pointerDown", "button": 0},
                        {"type": "pause", "duration": int(duration * 1000)},
                        {"type": "pointerUp", "button": 0},
                    ]
                }]
            }
            r = requests.post(
                f"{self.base_url}/session/{self.session_id}/actions",
                json=payload,
                timeout=self.timeout + duration
            )
            return r.status_code in (200, 204)
        except Exception as e:
            log.error(f"WDA press_and_hold error: {e}")
            return False

    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, duration: float = 0.3) -> bool:
        """Swipe / drag de la un punct la altul."""
        if not self.ensure_session():
            return False
        try:
            steps = max(10, int(duration * 30))
            actions_list = [
                {"type": "pointerMove", "duration": 0, "x": from_x, "y": from_y},
                {"type": "pointerDown", "button": 0},
            ]

            # Interpolare liniara pentru miscare fluida
            for i in range(1, steps + 1):
                t = i / steps
                ix = int(from_x + (to_x - from_x) * t)
                iy = int(from_y + (to_y - from_y) * t)
                actions_list.append({
                    "type": "pointerMove",
                    "duration": int(duration * 1000 / steps),
                    "x": ix, "y": iy
                })

            actions_list.append({"type": "pointerUp", "button": 0})

            payload = {
                "actions": [{
                    "type": "pointer",
                    "id": "finger1",
                    "parameters": {"pointerType": "touch"},
                    "actions": actions_list,
                }]
            }
            r = requests.post(
                f"{self.base_url}/session/{self.session_id}/actions",
                json=payload,
                timeout=self.timeout + duration
            )
            success = r.status_code in (200, 204)
            log.debug(f"WDA swipe ({from_x},{from_y})->({to_x},{to_y}): {'OK' if success else r.status_code}")
            return success
        except Exception as e:
            log.error(f"WDA swipe error: {e}")
            return False

    # Alias drag = swipe (cu hold mai lung)
    def drag(self, from_x: int, from_y: int, to_x: int, to_y: int) -> bool:
        return self.swipe(from_x, from_y, to_x, to_y, duration=0.6)

    def get_screenshot_b64(self) -> Optional[str]:
        """
        Ia screenshot de pe iPhone via WDA.
        Returneaza base64 PNG sau None.
        """
        if not self.ensure_session():
            return None
        try:
            r = requests.get(
                f"{self.base_url}/session/{self.session_id}/screenshot",
                timeout=15
            )
            if r.status_code == 200:
                data = r.json()
                return data.get("value")
            return None
        except Exception as e:
            log.error(f"WDA screenshot error: {e}")
            return None

    def get_screen_size(self) -> Tuple[int, int]:
        """Returneaza dimensiunea ecranului iPhone (width, height)."""
        if not self.ensure_session():
            return (390, 844)  # iPhone default fallback
        try:
            r = requests.get(
                f"{self.base_url}/session/{self.session_id}/window/size",
                timeout=self.timeout
            )
            if r.status_code == 200:
                data = r.json().get("value", {})
                return int(data.get("width", 390)), int(data.get("height", 844))
        except Exception:
            pass
        return (390, 844)

    def close_session(self):
        """Inchide sesiunea WDA."""
        if self.session_id:
            try:
                requests.delete(
                    f"{self.base_url}/session/{self.session_id}",
                    timeout=5
                )
            except Exception:
                pass
            self.session_id = None
