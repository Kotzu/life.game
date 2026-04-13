"""
YouTube Learner - versiune Juno/iPhone.

Nu foloseste Whisper (prea greu pentru iOS).
In schimb foloseste subtitrarea automata YouTube via yt-dlp --write-auto-subs.
Mult mai rapid si functioneaza perfect pe iPhone cu Juno.

Flux:
  1. yt-dlp descarca subtitrarea auto (.vtt / .srt) - fara video/audio
  2. Claude citeste subtitrarea si extrage strategii practice
  3. Strategiile se salveaza in knowledge_base.json

Utilizare:
  learner = YouTubeLearner(api_key="sk-ant-...")
  learner.learn_from_search("dota underlords best strategy 2024", "dota_underlords")
  learner.learn_from_url("https://youtube.com/watch?v=...", "dota_underlords")
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional

import anthropic

from kb import KnowledgeBase


SYSTEM_PROMPT = """Esti un expert analist de strategii pentru jocuri video.
Ti se da transcrierea unui video YouTube (din subtitrare automata).
Extrage informatii PRACTICE si SPECIFICE:
1. Strategii de joc concrete (ce sa faci, in ce ordine)
2. Prioritati clare (ce e mai important early/mid/late game)
3. Tips non-obvioase (informatii valoroase, nu lucruri evidente)
4. Greseli comune de evitat
5. Combinatii sau sinergii importante

Raspunde structurat, in romana. Fii concis si direct. Omite publicitate, intro, small talk.
"""


class YouTubeLearner:
    """YouTube learning optimizat pentru Juno/iPhone."""

    def __init__(self, api_key: str, kb: Optional[KnowledgeBase] = None):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.kb = kb or KnowledgeBase()
        self._check_ytdlp()

    def _check_ytdlp(self):
        """Verifica daca yt-dlp e instalat."""
        try:
            subprocess.run(["yt-dlp", "--version"], capture_output=True, check=True)
        except (FileNotFoundError, subprocess.CalledProcessError):
            print("⚠️  yt-dlp nu e instalat. Instalez acum...")
            subprocess.run([sys.executable, "-m", "pip", "install", "yt-dlp", "-q"], check=True)
            print("✅ yt-dlp instalat.")

    # ===== METODA PRINCIPALA: Cauta pe YouTube =====

    def learn_from_search(self, query: str, game: str, max_videos: int = 3) -> int:
        """
        Cauta pe YouTube si invata din primele N rezultate.
        Returneaza numarul de video-uri procesate cu succes.
        """
        print(f"\n🔍 Caut pe YouTube: '{query}'")
        print(f"   Max video-uri: {max_videos}")

        urls = self._search_urls(query, max_videos)
        if not urls:
            print("❌ Nu s-au gasit video-uri. Verifica conexiunea.")
            return 0

        print(f"✅ Gasit {len(urls)} video-uri. Incep invatarea...\n")
        success = 0
        for i, url in enumerate(urls, 1):
            print(f"📹 [{i}/{len(urls)}] {url}")
            ok = self.learn_from_url(url, game, show_prefix=f"  [{i}] ")
            if ok:
                success += 1

        print(f"\n✅ Invatare completata: {success}/{len(urls)} video-uri procesate.")
        self.kb.show_stats()
        return success

    def learn_from_url(self, url: str, game: str, show_prefix: str = "") -> bool:
        """
        Invata dintr-un URL YouTube specific.
        Returneaza True daca a reusit.
        """
        print(f"{show_prefix}📥 Descarc subtitrare...")

        subtitle_text = self._get_subtitles(url)
        if not subtitle_text:
            print(f"{show_prefix}❌ Nu am putut obtine subtitrarea.")
            return False

        print(f"{show_prefix}🧠 Analizez cu Claude ({len(subtitle_text)} chars)...")
        strategies = self._extract_strategies(subtitle_text, game, url)

        self.kb.add_youtube_knowledge(game, strategies, source=url)
        print(f"{show_prefix}✅ Strategii salvate!")

        # Afiseaza un preview
        preview = strategies[:300].replace('\n', ' ')
        print(f"{show_prefix}📌 Preview: {preview}...\n")
        return True

    def show_knowledge(self, game: str):
        """Afiseaza tot ce stie botul despre un joc."""
        knowledge = self.kb.get_all_knowledge(game)
        if not knowledge:
            print(f"❌ Nu exista cunostinte pentru '{game}'.")
            return
        print(f"\n{'='*50}")
        print(f"📚 CUNOSTINTE: {game}")
        print('='*50)
        print(knowledge)
        print('='*50)

    # ===== METODE INTERNE =====

    def _search_urls(self, query: str, max_results: int) -> List[str]:
        """Cauta pe YouTube si returneaza URL-urile."""
        search_expr = f"ytsearch{max_results}:{query}"
        cmd = [
            "yt-dlp",
            "--print", "webpage_url",
            "--no-playlist",
            "--quiet",
            "--no-warnings",
            search_expr,
        ]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            urls = [u.strip() for u in result.stdout.strip().splitlines() if u.strip()]
            return urls
        except Exception as e:
            print(f"Eroare cautare: {e}")
            return []

    def _get_subtitles(self, url: str) -> Optional[str]:
        """
        Descarca subtitrarea automata YouTube (fara audio/video).
        Mult mai rapid decat descarcarea audio + Whisper.
        """
        with tempfile.TemporaryDirectory() as tmpdir:
            cmd = [
                "yt-dlp",
                "--write-auto-subs",    # subtitrare automata YouTube
                "--sub-format", "vtt",  # format WebVTT
                "--sub-langs", "en",    # engleza (Underlords e in engleza)
                "--skip-download",      # NU descarca video/audio
                "--no-playlist",
                "--quiet",
                "--no-warnings",
                "--output", os.path.join(tmpdir, "%(id)s.%(ext)s"),
                url,
            ]
            try:
                subprocess.run(cmd, timeout=60, check=False)
            except subprocess.TimeoutExpired:
                print("⚠️  Timeout la descarcare subtitrare.")
                return None

            # Cauta fisierul .vtt descarcat
            vtt_files = list(Path(tmpdir).glob("*.vtt"))
            if not vtt_files:
                # Incearca cu subtitrare manuala (nu automata)
                return self._get_subtitles_manual(url, tmpdir)

            raw = vtt_files[0].read_text(encoding="utf-8", errors="ignore")
            return self._clean_vtt(raw)

    def _get_subtitles_manual(self, url: str, tmpdir: str) -> Optional[str]:
        """Fallback: subtitrare manuala daca auto nu exista."""
        cmd = [
            "yt-dlp",
            "--write-subs",
            "--sub-langs", "en",
            "--skip-download",
            "--no-playlist", "--quiet", "--no-warnings",
            "--output", os.path.join(tmpdir, "%(id)s.%(ext)s"),
            url,
        ]
        try:
            subprocess.run(cmd, timeout=60, check=False)
            vtt_files = list(Path(tmpdir).glob("*.vtt")) + list(Path(tmpdir).glob("*.srt"))
            if vtt_files:
                raw = vtt_files[0].read_text(encoding="utf-8", errors="ignore")
                return self._clean_vtt(raw)
        except Exception:
            pass
        return None

    def _clean_vtt(self, raw: str) -> str:
        """
        Curata fisierul VTT/SRT si extrage textul pur.
        Elimina timestamp-urile, tag-urile HTML, duplicatele.
        """
        # Elimina header VTT
        lines = raw.split('\n')
        text_lines = []
        seen = set()

        for line in lines:
            line = line.strip()
            # Skip timestamp lines (00:00:01.234 --> 00:00:02.567)
            if re.match(r'[\d:,\.]+ --> [\d:,\.]+', line):
                continue
            # Skip linii goale, numere (SRT), WEBVTT header
            if not line or line.isdigit() or line.startswith('WEBVTT') or line.startswith('NOTE'):
                continue
            # Elimina tag-uri HTML (<c>, <b>, etc.)
            line = re.sub(r'<[^>]+>', '', line).strip()
            # Elimina duplicatele consecutive (subtitrari suprapuse)
            if line and line not in seen:
                text_lines.append(line)
                seen.add(line)
                # Curata seen periodic
                if len(seen) > 50:
                    seen = set(text_lines[-20:])

        return ' '.join(text_lines)

    def _extract_strategies(self, text: str, game: str, url: str) -> str:
        """Trimite textul subtitrarii la Claude si extrage strategiile."""
        # Limita de 12000 chars per apel (suficient pentru un video)
        text_chunk = text[:12000]

        prompt = f"""Joc: {game}
Sursa: {url}

Transcriere video (din subtitrare YouTube):
\"\"\"
{text_chunk}
\"\"\"

Extrage toate informatiile practice si specifice pentru a juca {game} mai bine.
Organizeaza in sectiuni clare: Strategii Generale | Prioritati | Tips Specifice | Greseli de Evitat
"""
        try:
            msg = self.client.messages.create(
                model="claude-opus-4-6",
                max_tokens=2048,
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": prompt}],
            )
            return msg.content[0].text
        except Exception as e:
            return f"Eroare Claude: {e}\n\nText brut (primele 500 chars):\n{text[:500]}"
