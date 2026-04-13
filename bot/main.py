"""
Universal AI Game Bot - Main Entry Point
=========================================
Bot universal cu AI LLM pentru jocuri single-player/offline.
Suporta PC si iPhone (via WebDriverAgent).
Invata din YouTube, trial & error cu reward system, web dashboard.

Utilizare rapida:
  python main.py --web                          # Porneste dashboard-ul web
  python main.py --game dota_underlords         # Joaca pe PC
  python main.py --game dota_underlords --mobile # Joaca pe iPhone
  python main.py --game dota_underlords --learn-search "dota underlords guide"
"""

import argparse
import os
import sys
import threading
import time
from pathlib import Path

# PYTHONPATH
sys.path.insert(0, str(Path(__file__).parent))

from utils.config import load_config
from utils.logger import log
from core.vision_analyzer import VisionAnalyzer
from core.decision_engine import DecisionEngine
from learning.knowledge_base import KnowledgeBase
from learning.youtube_learner import YouTubeLearner
from learning.reward_system import RewardSystem


# ===== FACTORY: creeaza botul potrivit (PC sau iPhone) =====

def build_components(game_name: str, config: dict, mobile: bool):
    """
    Construieste screen capture + input controller potrivite pentru PC sau iPhone.
    Returneaza (screen_or_ios, input_ctrl, vision, game_bot)
    """
    vision = VisionAnalyzer(config)

    if mobile:
        from mobile.ios_controller import iOSController
        ios = iOSController(config)

        # Wrapper compatibil cu interfata BaseGame
        class MobileScreenAdapter:
            def capture_to_base64(self, max_width=1024):
                return ios.capture_to_base64(max_width)
            def get_screen_size(self):
                return ios.get_screen_size()
            def close(self):
                ios.close()

        class MobileInputAdapter:
            def __init__(self, ios_ctrl):
                self._ios = ios_ctrl
                # Expune metode compatibile cu InputController
                self.click = lambda x, y, **kw: ios_ctrl.tap(x, y)
                self.drag = lambda fx, fy, tx, ty: ios_ctrl.swipe(fx, fy, tx, ty, 0.5)
                self.press_key = lambda k: None  # iOS nu are tastatura in joc
                self.pause = lambda: time.sleep(0.5)
                self.move_to = lambda x, y: None  # Nu exista hover pe touch

        screen = MobileScreenAdapter()
        inp = MobileInputAdapter(ios)

        if not ios.connect():
            log.error("Conectare iPhone esuata. Verifica WDA.")
            sys.exit(1)
    else:
        from core.screen_capture import ScreenCapture
        from core.input_controller import InputController
        screen = ScreenCapture(monitor_index=config["capture"]["monitor"])
        inp = InputController(config)

    game_bot = _create_game_bot(game_name, config, screen, inp, vision)
    return screen, inp, vision, game_bot


def _create_game_bot(game_name, config, screen, inp, vision):
    if game_name == "dota_underlords":
        from games.dota_underlords import UnderlordsBot
        return UnderlordsBot(config, screen, inp, vision)
    raise ValueError(f"Joc necunoscut: {game_name}. Disponibil: dota_underlords")


# ===== BOT LOOP PRINCIPAL =====

# Flag global de stop (setat de dashboard sau CTRL+C)
_stop_flag = threading.Event()
_bot_thread = None


def run_bot(game_name: str, config: dict, mobile: bool = False,
            max_actions: int = 0, dashboard=None):
    """
    Loop principal al botului.
    Captureaza -> Analizeaza -> Decide -> Executa -> Reward -> Repeta.

    Args:
        dashboard: modulul web.dashboard (optional, pentru live updates)
    """
    global _stop_flag
    _stop_flag.clear()

    log.info(f"Pornesc bot: {game_name} | Mod: {'iPhone' if mobile else 'PC'}")
    if dashboard:
        dashboard.push_log(f"Bot pornit: {game_name}", "info")

    # Initializare
    screen, inp, vision, game_bot = build_components(game_name, config, mobile)
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    decision = DecisionEngine(config, kb)
    rewards = RewardSystem(game_name, kb)

    action_count = 0
    errors = 0
    MAX_ERRORS = 5
    prev_state = {}

    if dashboard:
        dashboard.update_state(running=True, game=game_name,
                               mode="mobile" if mobile else "desktop")

    # Countdown + auto-focus joc pe macOS
    import platform, subprocess
    log.info("=" * 55)
    log.info("  Deschide Dota Underlords ACUM si comuta pe fereastra!")
    log.info("  Botul porneste in 10 secunde...")
    log.info("=" * 55)
    for i in range(10, 0, -1):
        log.info(f"  Start in {i}s...")
        time.sleep(1)
    # Auto-focus Dota Underlords pe macOS
    if platform.system() == "Darwin":
        try:
            subprocess.run(
                ["osascript", "-e",
                 'tell application "Dota Underlords" to activate'],
                capture_output=True, timeout=3
            )
        except Exception:
            pass

    try:
        while not _stop_flag.is_set():
            if max_actions > 0 and action_count >= max_actions:
                log.info(f"Limita {max_actions} actiuni atinsa.")
                break

            # 1. Screenshot
            screenshot_b64 = screen.capture_to_base64()
            if screenshot_b64 is None:
                log.warning("Screenshot esuat. Reincerc...")
                time.sleep(2)
                continue

            if dashboard:
                dashboard.push_screenshot(screenshot_b64)

            # 2. UN singur apel Claude: vede + decide
            history_text = ""
            if hasattr(decision, 'history') and decision.history:
                recent = decision.history[-4:]
                history_text = "\n".join(
                    f"- {h.get('action')} pe '{h.get('target','')}' -> {h.get('result','?')}"
                    + (f" (ESEC: {h.get('notes','')})" if h.get('result') == 'esec' else "")
                    for h in recent
                )
            knowledge_text = kb.get_relevant_knowledge(game_name, {})

            result = vision.analyze_and_decide(screenshot_b64, history_text, knowledge_text)

            screen_type = result.get("screen", "unknown")
            action = {
                "action":   result.get("action", "wait"),
                "x_pct":    result.get("x_pct"),
                "y_pct":    result.get("y_pct"),
                "from_x_pct": result.get("from_x_pct"),
                "from_y_pct": result.get("from_y_pct"),
                "key":      result.get("key"),
                "reason":   result.get("reason", ""),
                "target_description": result.get("target", ""),
                "confidence": result.get("confidence", 0.5),
            }
            game_state = {
                "game":   game_name,
                "screen": screen_type,
                "gold":   result.get("gold"),
                "hp":     result.get("hp"),
                "round":  result.get("round"),
                "phase":  result.get("phase", "unknown"),
            }

            log.info(
                f"[{screen_type}] {action['action']} -> '{action['target_description']}' "
                f"({int(action['confidence']*100)}%) | {action['reason'][:60]}"
            )

            if dashboard:
                dashboard.update_state(
                    last_action=action,
                    game_state=game_state,
                    stats={"actions": action_count, "errors": errors, "uptime": 0},
                )
                dashboard.push_log(
                    f"[{screen_type}][{action['action']}] {action['reason'][:80]}", "info"
                )

            # 3. Fingerprint inainte
            fp_before = screen.fingerprint() if hasattr(screen, 'fingerprint') else None

            # 4. Executa
            success = game_bot.execute_action(action)

            # 5. Verifica daca ecranul s-a schimbat
            time.sleep(1.5)
            fp_after = screen.fingerprint() if hasattr(screen, 'fingerprint') else None
            screen_changed = (fp_before is None or fp_after is None or fp_before != fp_after)

            if success and screen_changed:
                errors = 0
                action_count += 1
                decision.mark_action_result(action, True)
            elif success and not screen_changed and action.get("action") != "wait":
                action_count += 1
                decision.mark_action_result(
                    action, False,
                    notes=f"Ecranul nu s-a schimbat dupa click pe '{action.get('target_description','?')}'"
                )
                log.warning(f"Click fara efect pe '{action.get('target_description','?')}'")
                if dashboard:
                    dashboard.push_log(
                        f"Click ratat pe '{action.get('target_description','?')}' - voi incerca altfel",
                        "warning"
                    )
            else:
                if action.get("action") == "wait":
                    pass  # wait e ok
                else:
                    errors += 1
                decision.mark_action_result(action, success)
                if errors >= MAX_ERRORS:
                    log.error(f"Prea multe erori ({MAX_ERRORS}). Opresc.")
                    break

            # 6. Reward bazat pe schimbarea starii
            new_screenshot_b64 = screen.capture_to_base64()
            if new_screenshot_b64:
                new_result = vision.analyze_and_decide(new_screenshot_b64)
                new_state = {
                    "game": game_name,
                    "screen": new_result.get("screen", "unknown"),
                    "gold": new_result.get("gold"),
                    "hp": new_result.get("hp"),
                    "round": new_result.get("round"),
                }
                reward = rewards.record_experience(game_state, action, new_state)
                log.debug(f"Reward: {reward:+.2f}")

                if (new_state.get("hp") or 100) <= 0:
                    log.info("Game over! Resetez episodul.")
                    rewards.reset_episode()
                    if dashboard:
                        dashboard.push_log("Game over! Episod nou.", "warning")
                    time.sleep(10)

            # 7. Pauza adaptiva: mai scurta pe meniu, mai lunga in joc
            if screen_type in ("main_menu", "mode_select"):
                time.sleep(0.5)  # Meniu: rapid
            else:
                fps = config["capture"].get("fps", 2)
                time.sleep(1.0 / fps)

    except KeyboardInterrupt:
        log.info("Bot oprit (CTRL+C)")
    finally:
        screen.close()
        summary = rewards.get_episode_summary()
        log.info(
            f"Sesiune terminata | Actiuni: {action_count} | "
            f"Reward total: {summary['total_reward']:+.1f} | "
            f"Runde: {summary['rounds_survived']}"
        )
        if dashboard:
            dashboard.update_state(running=False)
            dashboard.push_log(
                f"Bot oprit. Actiuni: {action_count}, Reward: {summary['total_reward']:+.1f}",
                "info"
            )


def start_bot_thread(game_name, config, mobile, max_actions=0, dashboard=None):
    """Porneste botul intr-un thread separat (pentru dashboard)."""
    global _bot_thread, _stop_flag
    _stop_flag.clear()
    _bot_thread = threading.Thread(
        target=run_bot,
        kwargs=dict(game_name=game_name, config=config, mobile=mobile,
                    max_actions=max_actions, dashboard=dashboard),
        daemon=True,
    )
    _bot_thread.start()


def stop_bot_thread():
    """Opreste thread-ul botului."""
    global _stop_flag
    _stop_flag.set()
    log.info("Semnal de oprire trimis.")


# ===== YOUTUBE LEARNING =====

def learn_from_youtube(game_name: str, url: str, config: dict, dashboard=None):
    """Invata dintr-un URL specific."""
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    learner = YouTubeLearner(config, kb)
    if dashboard:
        dashboard.push_log(f"Invatare din URL: {url[:60]}...", "info")
    strategies = learner.learn_from_url(url, game_name)
    log.info("=== Strategii extrase ===")
    print(strategies)
    if dashboard:
        dashboard.push_log("Invatare URL completata!", "success")
        dashboard.update_state(kb_stats=kb.get_stats())


def search_youtube(game_name: str, query: str, config: dict,
                   max_videos: int = 3, list_only: bool = False, dashboard=None):
    """Cauta pe YouTube si invata."""
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    learner = YouTubeLearner(config, kb)

    if list_only:
        videos = learner.get_video_titles(query, max_videos=10)
        if not videos:
            log.error("Nu s-au gasit video-uri.")
            return
        print(f"\n=== Video-uri pentru '{query}' ===")
        for i, v in enumerate(videos, 1):
            print(f"  {i}. [{v['duration']}] {v['title']}")
            print(f"     {v['url']}")
        return

    if dashboard:
        dashboard.push_log(f"Caut YouTube: '{query}' ({max_videos} video-uri)", "info")

    results = learner.search_and_learn(query, game_name, max_videos=max_videos)

    if results:
        log.info(f"Invatat din {len(results)} video-uri!")
        if dashboard:
            dashboard.push_log(f"Invatare YouTube completata! ({len(results)} video-uri)", "success")
            dashboard.update_state(kb_stats=kb.get_stats())
    else:
        log.error("Nu s-a putut invata nimic. Verifica yt-dlp si conexiunea.")
        if dashboard:
            dashboard.push_log("Eroare invatare YouTube!", "error")


def learn_callback_factory(config, dashboard):
    """Factory pentru callback-ul de invatare din dashboard."""
    def _learn(game: str, query: str = "", url: str = "", max_videos: int = 3):
        if url:
            learn_from_youtube(game, url, config, dashboard)
        elif query:
            search_youtube(game, query, config, max_videos=max_videos, dashboard=dashboard)
    return _learn


# ===== ALTE COMENZI =====

def describe_screen(config: dict, mobile: bool = False):
    """Debug: descrie ce vede botul."""
    if mobile:
        from mobile.ios_controller import iOSController
        ios = iOSController(config)
        if not ios.connect():
            return
        b64 = ios.capture_to_base64()
        ios.close()
    else:
        from core.screen_capture import ScreenCapture
        screen = ScreenCapture(monitor_index=config["capture"]["monitor"])
        b64 = screen.capture_to_base64()
        screen.close()

    if not b64:
        log.error("Nu s-a putut captura ecranul.")
        return

    vision = VisionAnalyzer(config)
    desc = vision.describe_scene(b64)
    print("\n=== Ce vede botul ===")
    print(desc)


def add_strategy(game_name: str, text: str, config: dict):
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    kb.add_strategy(game_name, text)
    log.info(f"Strategie adaugata: {text}")


def show_kb_stats(config: dict):
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    stats = kb.get_stats()
    print("\n=== Knowledge Base ===")
    print(f"Jocuri:    {', '.join(stats['games']) or 'niciunul'}")
    print(f"Strategii: {stats['total_strategies']}")
    print(f"Experiente:{stats['total_experiences']}")
    print(f"YouTube:   {stats['youtube_sources']} surse")


def get_local_ip() -> str:
    """Returneaza IP-ul local al PC-ului (pentru dashboard)."""
    import socket
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "localhost"


# ===== MAIN =====

def main():
    parser = argparse.ArgumentParser(
        description="Universal AI Game Bot - LLM + Vision + Trial&Error + YouTube",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemple:
  # Dashboard web (acceseaza de pe iPhone: http://<IP-PC>:5000)
  python main.py --web

  # Joaca pe PC
  python main.py --game dota_underlords

  # Joaca pe iPhone (WDA trebuie sa ruleze)
  python main.py --game dota_underlords --mobile

  # Dashboard + iPhone (tot de la dashboard controlezi)
  python main.py --web --mobile

  # Invata din YouTube (cautare automata)
  python main.py --game dota_underlords --learn-search "dota underlords best guide 2024"

  # Listeaza video-uri fara sa descarce
  python main.py --learn-search "underlords tier list" --list-videos

  # URL specific
  python main.py --game dota_underlords --learn-url "https://youtube.com/watch?v=..."

  # Debug - ce vede botul
  python main.py --describe
  python main.py --describe --mobile

  # Statistici
  python main.py --kb-stats
        """
    )

    parser.add_argument("--game", "-g", type=str, default="dota_underlords",
                        help="Jocul de jucat (default: dota_underlords)")
    parser.add_argument("--mobile", "-m", action="store_true",
                        help="Mod iPhone: controleaza via WDA (WebDriverAgent)")
    parser.add_argument("--web", "-w", action="store_true",
                        help="Porneste dashboard-ul web (accesibil din orice browser)")
    parser.add_argument("--web-port", type=int, default=5000,
                        help="Port pentru dashboard web (default: 5000)")
    parser.add_argument("--learn-url", "-l", type=str,
                        help="URL YouTube specific")
    parser.add_argument("--learn-search", type=str, metavar="QUERY",
                        help="Cauta pe YouTube si invata (ex: 'dota underlords guide')")
    parser.add_argument("--max-videos", type=int, default=3,
                        help="Numar maxim video-uri la --learn-search (default: 3)")
    parser.add_argument("--list-videos", action="store_true",
                        help="Listeaza video-urile fara sa le descarce")
    parser.add_argument("--describe", "-d", action="store_true",
                        help="Descrie ecranul curent (debug)")
    parser.add_argument("--add-strategy", "-s", type=str,
                        help="Adauga o strategie manuala")
    parser.add_argument("--kb-stats", action="store_true",
                        help="Afiseaza statistici knowledge base")
    parser.add_argument("--max-actions", "-n", type=int, default=0,
                        help="Limita actiuni (0 = infinit)")
    parser.add_argument("--config", "-c", type=str, default=None,
                        help="Cale config YAML custom")
    parser.add_argument("--api-key", type=str,
                        help="Anthropic API key (sau env ANTHROPIC_API_KEY)")

    args = parser.parse_args()

    if args.api_key:
        os.environ["ANTHROPIC_API_KEY"] = args.api_key

    config = load_config(args.config)

    api_key_env = config["ai"]["api_key_env"]
    if not os.environ.get(api_key_env):
        log.error(f"API key lipsa! Seteaza {api_key_env} sau --api-key")
        sys.exit(1)

    os.makedirs("logs", exist_ok=True)
    os.makedirs("data", exist_ok=True)

    # ===== WEB DASHBOARD =====
    if args.web:
        from web.dashboard import run_dashboard, set_callbacks, update_state
        import web.dashboard as dashboard_mod

        kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
        dashboard_mod.update_state(kb_stats=kb.get_stats())

        # Seteaza callback-urile
        def _start(game, mode):
            mobile = (mode == "mobile")
            start_bot_thread(game, config, mobile,
                             max_actions=args.max_actions,
                             dashboard=dashboard_mod)

        set_callbacks(
            start_fn=_start,
            stop_fn=stop_bot_thread,
            learn_fn=learn_callback_factory(config, dashboard_mod),
        )

        local_ip = get_local_ip()
        log.info(f"Dashboard pornit!")
        log.info(f"  PC:     http://localhost:{args.web_port}")
        log.info(f"  iPhone: http://{local_ip}:{args.web_port}")

        # Daca --game si --web, porneste botul automat
        if args.game and not args.learn_search and not args.learn_url:
            log.info(f"Pornesc botul automat pentru {args.game}...")
            start_bot_thread(args.game, config, args.mobile,
                             max_actions=args.max_actions,
                             dashboard=dashboard_mod)

        run_dashboard(port=args.web_port)
        return

    # ===== COMENZI FARA DASHBOARD =====

    if args.describe:
        describe_screen(config, mobile=args.mobile)

    elif args.kb_stats:
        show_kb_stats(config)

    elif args.learn_url:
        learn_from_youtube(args.game, args.learn_url, config)

    elif args.learn_search:
        search_youtube(args.game, args.learn_search, config,
                       max_videos=args.max_videos, list_only=args.list_videos)

    elif args.add_strategy:
        add_strategy(args.game, args.add_strategy, config)

    elif args.game:
        run_bot(args.game, config, mobile=args.mobile, max_actions=args.max_actions)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
