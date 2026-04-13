"""
YouTube Learner - Descarca si analizeaza video-uri YouTube pentru strategii.
Foloseste yt-dlp pentru download si Whisper pentru transcriptie audio.
Claude analizeaza transcriptia si extrage strategii aplicabile in-game.
"""

import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional

import anthropic

from utils.logger import log


EXTRACT_SYSTEM_PROMPT = """Esti un expert analist de strategii pentru jocuri video.
Ti se da o transcriptie a unui video YouTube cu gameplay sau ghid de joc.
Sarcina ta este sa extragi informatii PRACTICE si SPECIFICE despre:
1. Strategii de joc (ce sa faci, in ce ordine)
2. Decizii importante (cand sa faci X vs Y)
3. Tips si tricks (informatii ascunse sau non-obvioase)
4. Prioritati (ce e mai important)
5. Greseli comune de evitat

Raspunde in romana. Fii concis si practic.
"""


class YouTubeLearner:
    """
    Invata strategii din video-uri YouTube.
    Pipeline: YouTube URL -> Audio -> Transcript (Whisper) -> Strategii (Claude)
    """

    def __init__(self, config: dict, knowledge_base):
        import os
        api_key = os.environ.get(config["ai"]["api_key_env"])
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = config["ai"]["model"]
        self.knowledge_base = knowledge_base
        self.whisper_model = config["learning"]["whisper_model"]
        self.cache_dir = Path(config["learning"]["video_cache_path"])
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        log.info("YouTubeLearner initializat")

    def learn_from_url(self, url: str, game_name: str) -> str:
        """
        Principala metoda: invata din URL-ul unui video YouTube.

        1. Descarca audio-ul
        2. Transcriere cu Whisper
        3. Analiza cu Claude
        4. Salveaza in knowledge base

        Returns:
            Strategiile extrase ca text
        """
        log.info(f"Incep invatarea din: {url}")

        # Step 1: Descarca audio
        audio_path = self._download_audio(url)
        if not audio_path:
            return "Eroare: nu s-a putut descarca audio-ul"

        # Step 2: Transcriere cu Whisper
        transcript = self._transcribe(audio_path)
        if not transcript:
            return "Eroare: nu s-a putut transcrie audio-ul"

        log.info(f"Transcript obtinut: {len(transcript)} caractere")

        # Step 3: Analiza cu Claude
        strategies = self._extract_strategies(transcript, game_name, url)

        # Step 4: Salveaza in knowledge base
        self.knowledge_base.add_youtube_knowledge(game_name, strategies, url)

        # Curata fisierele temporare
        try:
            os.remove(audio_path)
        except Exception:
            pass

        log.info(f"Invatare completata! Extras {len(strategies)} caractere de strategii.")
        return strategies

    def learn_from_multiple_urls(self, urls: List[str], game_name: str) -> List[str]:
        """Invata din mai multe URL-uri YouTube."""
        results = []
        for i, url in enumerate(urls, 1):
            log.info(f"Procesez video {i}/{len(urls)}: {url}")
            result = self.learn_from_url(url, game_name)
            results.append(result)
        return results

    def search_and_learn(self, query: str, game_name: str, max_videos: int = 3) -> List[str]:
        """
        Cauta pe YouTube dupa query si invata din primele N video-uri.
        Foloseste yt-dlp cu ytsearchN: pentru a cauta fara API key YouTube.

        Exemplu: search_and_learn("dota underlords best strategy guide", "dota_underlords", 3)
        """
        log.info(f"Caut pe YouTube: '{query}' (primele {max_videos} video-uri)")

        # yt-dlp suporta ytsearchN:query nativ
        search_url = f"ytsearch{max_videos}:{query}"

        # Obtine lista de URL-uri din search
        cmd = [
            "yt-dlp",
            "--get-url",
            "--no-playlist",
            "--quiet",
            search_url,
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            urls = [u.strip() for u in result.stdout.strip().split('\n') if u.strip()]

            if not urls:
                # Fallback: obtine ID-urile si construieste URL-urile
                cmd2 = [
                    "yt-dlp",
                    "--print", "webpage_url",
                    "--no-playlist",
                    "--quiet",
                    search_url,
                ]
                result2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=60)
                urls = [u.strip() for u in result2.stdout.strip().split('\n') if u.strip()]

            if not urls:
                log.error(f"Nu s-au gasit video-uri pentru: '{query}'")
                return []

            log.info(f"Gasit {len(urls)} video-uri. Incep invatarea...")
            for i, url in enumerate(urls, 1):
                log.info(f"  [{i}/{len(urls)}] {url}")

            return self.learn_from_multiple_urls(urls, game_name)

        except subprocess.TimeoutExpired:
            log.error("Timeout la cautarea YouTube")
            return []
        except Exception as e:
            log.error(f"Eroare la cautare YouTube: {e}")
            return []

    def get_video_titles(self, query: str, max_videos: int = 10) -> List[dict]:
        """
        Returneaza titlurile si URL-urile video-urilor gasite fara sa le descarce.
        Util pentru a alege manual ce video-uri sa folosesti.
        """
        search_url = f"ytsearch{max_videos}:{query}"
        cmd = [
            "yt-dlp",
            "--print", "%(title)s\t%(webpage_url)s\t%(duration_string)s",
            "--no-playlist",
            "--quiet",
            search_url,
        ]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            videos = []
            for line in result.stdout.strip().split('\n'):
                if '\t' in line:
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        videos.append({
                            "title": parts[0],
                            "url": parts[1],
                            "duration": parts[2] if len(parts) > 2 else "?",
                        })
            return videos
        except Exception as e:
            log.error(f"Eroare la listare video-uri: {e}")
            return []

    def _download_audio(self, url: str) -> Optional[str]:
        """Descarca audio-ul din YouTube folosind yt-dlp."""
        output_path = str(self.cache_dir / "audio_%(id)s.%(ext)s")

        cmd = [
            "yt-dlp",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "5",       # Calitate medie (suficienta pentru Whisper)
            "--no-playlist",
            "--quiet",
            "--output", output_path,
            "--print", "after_move:filepath",  # Afiseaza calea fisierului
            url,
        ]

        try:
            log.info("Descarc audio din YouTube...")
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)

            if result.returncode != 0:
                log.error(f"yt-dlp eroare: {result.stderr}")
                return None

            # Gaseste fisierul descarcat
            downloaded_path = result.stdout.strip().split('\n')[-1]
            if os.path.exists(downloaded_path):
                log.info(f"Audio descarcat: {downloaded_path}")
                return downloaded_path

            # Fallback: cauta fisierul in cache dir
            for f in self.cache_dir.glob("audio_*.mp3"):
                return str(f)

            return None

        except subprocess.TimeoutExpired:
            log.error("Timeout la descarcare video")
            return None
        except Exception as e:
            log.error(f"Eroare la descarcare: {e}")
            return None

    def _transcribe(self, audio_path: str) -> Optional[str]:
        """Transcriere audio cu Whisper."""
        try:
            import whisper
            log.info(f"Transcriu audio cu Whisper ({self.whisper_model})...")
            model = whisper.load_model(self.whisper_model)
            result = model.transcribe(audio_path, fp16=False)
            return result["text"]
        except ImportError:
            log.warning("Whisper nu e instalat. Incerc cu whisper CLI...")
            return self._transcribe_cli(audio_path)
        except Exception as e:
            log.error(f"Eroare Whisper: {e}")
            return None

    def _transcribe_cli(self, audio_path: str) -> Optional[str]:
        """Alternativa: transcriere cu whisper CLI."""
        try:
            output_dir = str(self.cache_dir)
            cmd = [
                "whisper", audio_path,
                "--model", self.whisper_model,
                "--output_format", "txt",
                "--output_dir", output_dir,
                "--language", "en",  # Dota Underlords e in engleza
            ]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

            if result.returncode == 0:
                # Gaseste fisierul txt generat
                base = Path(audio_path).stem
                txt_path = self.cache_dir / f"{base}.txt"
                if txt_path.exists():
                    return txt_path.read_text(encoding="utf-8")

            log.error(f"whisper CLI eroare: {result.stderr}")
            return None
        except Exception as e:
            log.error(f"Eroare whisper CLI: {e}")
            return None

    def _extract_strategies(self, transcript: str, game_name: str, source_url: str) -> str:
        """
        Foloseste Claude pentru a extrage strategii utile din transcript.
        Segmenteaza transcriptia daca e prea lunga.
        """
        MAX_CHUNK = 8000  # Caractere per chunk (Claude are context lung)

        if len(transcript) <= MAX_CHUNK:
            return self._analyze_chunk(transcript, game_name, source_url)

        # Segmenteaza si analizeaza pe bucati
        log.info(f"Transcript lung ({len(transcript)} chars), segmentez...")
        chunks = [transcript[i:i + MAX_CHUNK] for i in range(0, len(transcript), MAX_CHUNK)]
        all_strategies = []

        for i, chunk in enumerate(chunks[:5], 1):  # Max 5 chunk-uri
            log.info(f"Analizez chunk {i}/{min(len(chunks), 5)}...")
            result = self._analyze_chunk(chunk, game_name, source_url, chunk_num=i)
            all_strategies.append(result)

        # Combina si deduplica
        combined = "\n\n".join(all_strategies)
        return self._dedup_strategies(combined, game_name)

    def _analyze_chunk(self, text: str, game_name: str, url: str, chunk_num: int = 1) -> str:
        """Analizeaza un chunk de transcript cu Claude."""
        prompt = f"""Joc: {game_name}
Sursa: {url}
Parte: {chunk_num}

Transcript video:
\"\"\"
{text}
\"\"\"

Extrage toate informatiile PRACTICE si SPECIFICE despre cum sa joci {game_name} mai bine.
Organizeaza pe categorii: Strategii generale, Prioritati, Tips specifice, Greseli de evitat.
Fii concis si direct la subiect. Omite parti irelevante din transcript (publicitate, small talk, etc.)
"""
        message = self.client.messages.create(
            model=self.model,
            max_tokens=2048,
            system=EXTRACT_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )
        return message.content[0].text

    def _dedup_strategies(self, combined: str, game_name: str) -> str:
        """Deduplica si consolideaza strategiile extrase."""
        prompt = f"""Ai urmatoarele strategii extrase din mai multe parti ale unui video despre {game_name}.
Consolideaza-le intr-un ghid coerent, eliminand duplicatele.

{combined[:6000]}

Returneaza un ghid structurat si practic, fara duplicate.
"""
        message = self.client.messages.create(
            model=self.model,
            max_tokens=2048,
            system=EXTRACT_SYSTEM_PROMPT,
            messages=[{"role": "user", "content": prompt}],
        )
        return message.content[0].text
