"""
Universal AI Game Bot - Main Entry Point
=========================================
Bot universal full offline cu baza AI LLM.
Invata din YouTube, joaca orice joc single player.

Utilizare:
    # Joaca Dota Underlords
    python main.py --game dota_underlords

    # Invata din YouTube inainte de a juca
    python main.py --game dota_underlords --learn-url "https://youtube.com/watch?v=..."

    # Analizeaza ecranul curent (debug)
    python main.py --describe

    # Adauga strategii manual
    python main.py --game dota_underlords --add-strategy "Prioritizeaza aliantele Warriors si Assassins early game"
"""

import argparse
import os
import sys
import time
from pathlib import Path

# Adauga directorul botului in PYTHONPATH
sys.path.insert(0, str(Path(__file__).parent))

from utils.config import load_config
from utils.logger import log
from core.screen_capture import ScreenCapture
from core.input_controller import InputController
from core.vision_analyzer import VisionAnalyzer
from core.decision_engine import DecisionEngine
from learning.knowledge_base import KnowledgeBase
from learning.youtube_learner import YouTubeLearner


def create_game_bot(game_name: str, config: dict, screen, inp, vision):
    """Factory: creeaza botul specific jocului."""
    if game_name == "dota_underlords":
        from games.dota_underlords import UnderlordsBot
        return UnderlordsBot(config, screen, inp, vision)
    else:
        raise ValueError(f"Joc necunoscut: {game_name}. Jocuri suportate: dota_underlords")


def run_bot(game_name: str, config: dict, max_actions: int = 0):
    """
    Loop principal al botului.
    Captureaza ecranul -> Analizeaza -> Decide -> Executa -> Repeta.
    """
    log.info(f"Pornesc botul pentru: {game_name}")

    # Initializare componente
    screen = ScreenCapture(monitor_index=config["capture"]["monitor"])
    inp = InputController(config)
    vision = VisionAnalyzer(config)
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    decision = DecisionEngine(config, kb)
    game_bot = create_game_bot(game_name, config, screen, inp, vision)

    log.info("Toate componentele initializate. Incep in 3 secunde...")
    log.info("CTRL+C pentru a opri.")
    time.sleep(3)

    action_count = 0
    errors = 0
    MAX_ERRORS = 5

    try:
        while True:
            # Verifica limita actiunilor
            if max_actions > 0 and action_count >= max_actions:
                log.info(f"Limita de {max_actions} actiuni atinsa. Opresc.")
                break

            # 1. Captureaza ecranul
            log.debug("Capturez ecranul...")
            screenshot_b64 = screen.capture_to_base64()

            # 2. Verifica daca jocul e activ
            if not game_bot.is_game_active(screenshot_b64):
                log.warning("Jocul nu pare activ pe ecran. Astept 5s...")
                time.sleep(5)
                continue

            # 3. Parseaza starea jocului
            log.debug("Analizez starea jocului...")
            game_state = game_bot.parse_game_state(screenshot_b64)
            log.info(f"Stare: Round={game_state.get('round')} Gold={game_state.get('gold')} HP={game_state.get('hp')}")

            # 4. Decide actiunea
            action = decision.decide(game_state, screenshot_b64, game_name)
            log.info(f"Decizie: {action.get('action')} | Incredere: {action.get('confidence', 0):.0%}")

            # 5. Executa actiunea
            success = game_bot.execute_action(action)

            if success:
                errors = 0
                action_count += 1
                decision.mark_action_result(action, True)
            else:
                errors += 1
                decision.mark_action_result(action, False, "Executie esuata")
                if errors >= MAX_ERRORS:
                    log.error(f"Prea multe erori ({MAX_ERRORS}). Opresc.")
                    break

            # 6. Pauza intre actiuni (evita spam)
            fps = config["capture"]["fps"]
            time.sleep(1.0 / fps)

    except KeyboardInterrupt:
        log.info("Bot oprit manual (CTRL+C)")
    finally:
        screen.close()
        log.info(f"Total actiuni executate: {action_count}")


def learn_from_youtube(game_name: str, url: str, config: dict):
    """Invata strategii dintr-un video YouTube (URL specific)."""
    log.info(f"Incep invatarea din YouTube pentru: {game_name}")
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    learner = YouTubeLearner(config, kb)

    strategies = learner.learn_from_url(url, game_name)

    log.info("=== Strategii extrase ===")
    print(strategies)
    log.info("Invatare completata! Strategiile au fost salvate in knowledge base.")


def search_youtube(game_name: str, query: str, config: dict, max_videos: int = 3, list_only: bool = False):
    """Cauta pe YouTube si invata din video-urile gasite."""
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    learner = YouTubeLearner(config, kb)

    if list_only:
        # Listeaza video-urile fara sa le descarce
        log.info(f"Caut video-uri pentru: '{query}'")
        videos = learner.get_video_titles(query, max_videos=10)
        if not videos:
            log.error("Nu s-au gasit video-uri.")
            return
        print(f"\n=== Video-uri gasite pentru '{query}' ===")
        for i, v in enumerate(videos, 1):
            print(f"  {i}. [{v['duration']}] {v['title']}")
            print(f"     {v['url']}")
        print(f"\nFoloseste --learn-url <URL> pentru a invata dintr-un video specific.")
        print(f"Sau --learn-search '{query}' --max-videos {max_videos} pentru a invata automat.")
        return

    # Cauta si invata automat
    results = learner.search_and_learn(query, game_name, max_videos=max_videos)
    if results:
        log.info(f"Invatare completata din {len(results)} video-uri!")
        log.info("Ruleaza --kb-stats pentru a vedea ce s-a invatat.")
    else:
        log.error("Nu s-a putut invata nimic. Verifica conexiunea si yt-dlp.")


def describe_screen(config: dict):
    """Descrie ce vede botul pe ecran (mod debug)."""
    screen = ScreenCapture(monitor_index=config["capture"]["monitor"])
    vision = VisionAnalyzer(config)

    log.info("Capturez ecranul si solicit descriere...")
    screenshot_b64 = screen.capture_to_base64()
    description = vision.describe_scene(screenshot_b64)

    print("\n=== Ce vede botul ===")
    print(description)
    screen.close()


def add_strategy(game_name: str, strategy_text: str, config: dict):
    """Adauga o strategie manuala in knowledge base."""
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    kb.add_strategy(game_name, strategy_text)
    log.info(f"Strategie adaugata pentru {game_name}: {strategy_text}")


def show_kb_stats(config: dict):
    """Afiseaza statistici despre knowledge base."""
    kb = KnowledgeBase(config["learning"]["knowledge_base_path"])
    stats = kb.get_stats()
    print("\n=== Knowledge Base Stats ===")
    print(f"Jocuri: {', '.join(stats['games']) or 'niciun joc'}")
    print(f"Strategii totale: {stats['total_strategies']}")
    print(f"Experiente totale: {stats['total_experiences']}")
    print(f"Surse YouTube: {stats['youtube_sources']}")


def main():
    parser = argparse.ArgumentParser(
        description="Universal AI Game Bot - LLM powered, offline games",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemple:
  # Joaca Dota Underlords
  python main.py --game dota_underlords

  # Cauta automat pe YouTube si invata din 3 video-uri
  python main.py --game dota_underlords --learn-search "dota underlords best strategy guide 2024"

  # Listeaza video-urile gasite fara sa invete (alegi tu)
  python main.py --learn-search "dota underlords tier list" --list-videos

  # Invata dintr-un URL specific
  python main.py --game dota_underlords --learn-url "https://youtube.com/watch?v=..."

  # Invata din mai multe video-uri
  python main.py --game dota_underlords --learn-search "underlords guide" --max-videos 5

  # Debug: ce vede botul pe ecran
  python main.py --describe

  # Adauga strategie manuala
  python main.py --game dota_underlords --add-strategy "Prioritizeaza Warriors early"

  # Statistici knowledge base
  python main.py --kb-stats
        """
    )

    parser.add_argument("--game", "-g", type=str, help="Jocul de jucat (ex: dota_underlords)")
    parser.add_argument("--learn-url", "-l", type=str, help="URL YouTube specific din care sa invete")
    parser.add_argument("--learn-search", type=str, metavar="QUERY",
                        help="Cauta pe YouTube si invata automat (ex: 'dota underlords guide')")
    parser.add_argument("--max-videos", type=int, default=3,
                        help="Numar maxim de video-uri de invatat la --learn-search (default: 3)")
    parser.add_argument("--list-videos", action="store_true",
                        help="Folosit cu --learn-search: listeaza video-urile fara sa invete")
    parser.add_argument("--describe", "-d", action="store_true", help="Descrie ecranul curent (debug)")
    parser.add_argument("--add-strategy", "-s", type=str, help="Adauga o strategie manuala")
    parser.add_argument("--kb-stats", action="store_true", help="Afiseaza statistici knowledge base")
    parser.add_argument("--max-actions", "-n", type=int, default=0, help="Limita maxima de actiuni (0 = infinit)")
    parser.add_argument("--config", "-c", type=str, default=None, help="Cale config YAML custom")
    parser.add_argument("--api-key", type=str, help="Anthropic API key (sau seteaza ANTHROPIC_API_KEY env)")

    args = parser.parse_args()

    # Seteaza API key daca a fost furnizat
    if args.api_key:
        os.environ["ANTHROPIC_API_KEY"] = args.api_key

    # Verifica API key
    config = load_config(args.config)
    api_key_env = config["ai"]["api_key_env"]
    if not os.environ.get(api_key_env):
        log.error(f"API key lipsa! Seteaza {api_key_env} sau foloseste --api-key")
        log.error("Exemplu: export ANTHROPIC_API_KEY='sk-ant-...'")
        sys.exit(1)

    # Creeaza directoarele necesare
    os.makedirs("logs", exist_ok=True)
    os.makedirs("data", exist_ok=True)

    # Executa comanda solicitata
    if args.describe:
        describe_screen(config)

    elif args.kb_stats:
        show_kb_stats(config)

    elif args.learn_url:
        if not args.game:
            log.error("Trebuie sa specifici --game pentru a invata din YouTube")
            sys.exit(1)
        learn_from_youtube(args.game, args.learn_url, config)

    elif args.learn_search:
        if not args.game and not args.list_videos:
            log.error("Trebuie sa specifici --game pentru a invata din YouTube")
            sys.exit(1)
        game = args.game or "general"
        search_youtube(game, args.learn_search, config,
                       max_videos=args.max_videos, list_only=args.list_videos)

    elif args.add_strategy:
        if not args.game:
            log.error("Trebuie sa specifici --game pentru a adauga o strategie")
            sys.exit(1)
        add_strategy(args.game, args.add_strategy, config)

    elif args.game:
        run_bot(args.game, config, max_actions=args.max_actions)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
