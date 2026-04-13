"""
Reward System - Trial & Error cu reinforcement learning simplificat.

Botul primeste reward/penalty dupa fiecare actiune bazat pe cum s-a schimbat
starea jocului. Claude foloseste acest feedback pentru a imbunatatii deciziile.

Rewards pozitive: supravietuire runda, gold crescut, HP mentinut, eroi combinati
Rewards negative: HP pierdut, gold irosit, eliminat din joc

Toate experientele sunt salvate in Knowledge Base si folosite ca context
pentru deciziile viitoare (few-shot learning cu exemple reale).
"""

import json
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from utils.logger import log


@dataclass
class GameSnapshot:
    """Snapshot al starii jocului la un moment dat."""
    gold: int = 0
    hp: int = 100
    round_num: int = 0
    level: int = 1
    board_count: int = 0
    bench_count: int = 0
    phase: str = "unknown"


@dataclass
class Experience:
    """O experienta completa: stare -> actiune -> stare noua -> reward."""
    state_before: Dict[str, Any] = field(default_factory=dict)
    action: Dict[str, Any] = field(default_factory=dict)
    state_after: Dict[str, Any] = field(default_factory=dict)
    reward: float = 0.0
    reward_breakdown: Dict[str, float] = field(default_factory=dict)
    lesson: str = ""  # Ce am invatat din aceasta experienta


class RewardSystem:
    """
    Calculeaza reward-uri pe baza schimbarii starii jocului.
    Adaptat pentru Dota Underlords, dar extensibil pentru orice joc.
    """

    def __init__(self, game_name: str, knowledge_base):
        self.game_name = game_name
        self.kb = knowledge_base
        self.episode_experiences: List[Experience] = []
        self.total_reward = 0.0
        self.prev_snapshot: Optional[GameSnapshot] = None
        self.rounds_survived = 0
        self.max_round = 0

        log.info(f"RewardSystem initializat pentru {game_name}")

    def compute_reward(
        self,
        state_before: Dict[str, Any],
        action: Dict[str, Any],
        state_after: Dict[str, Any],
    ) -> float:
        """
        Calculeaza reward-ul pentru o tranzitie de stare.
        Returneaza valoarea reward-ului (-10 ... +10).
        """
        before = self._snap(state_before)
        after = self._snap(state_after)
        breakdown = {}

        reward = 0.0

        # ===== REWARD: Supravietuire runda =====
        if after.round_num > before.round_num:
            r = 2.0
            reward += r
            breakdown["round_survived"] = r
            self.rounds_survived += 1
            self.max_round = max(self.max_round, after.round_num)

        # ===== REWARD: HP mentinut =====
        hp_delta = after.hp - before.hp
        if hp_delta < 0:
            r = hp_delta * 0.15  # -0.15 per HP pierdut
            reward += r
            breakdown["hp_lost"] = r
        elif hp_delta == 0 and after.phase == "combat":
            r = 0.5  # Bonus pentru HP mentinut in lupta
            reward += r
            breakdown["hp_maintained"] = r

        # ===== REWARD: Gold management =====
        gold_delta = after.gold - before.gold
        action_type = action.get("action", "wait")

        if action_type == "reroll":
            # Reroll cu gold sub 10 = penalitate (irosesti interes compus)
            if before.gold < 10:
                r = -0.5
                reward += r
                breakdown["risky_reroll"] = r
            elif before.gold >= 20:
                r = 0.2  # Reroll cu gold suficient = ok
                reward += r
                breakdown["safe_reroll"] = r

        if action_type == "buy":
            # Cumparare = good daca board-ul are loc si e util
            if after.board_count > before.board_count:
                r = 0.8
                reward += r
                breakdown["hero_bought_placed"] = r

        if action_type == "level_up":
            # Level up = good daca ai gold suficient si esti in runda potrivita
            if before.gold >= before.level + 2:
                r = 0.6
                reward += r
                breakdown["level_up_affordable"] = r
            else:
                r = -0.3
                reward += r
                breakdown["level_up_broke"] = r

        # ===== REWARD: Combine eroi (3 -> 1 star 2) =====
        # Daca numarul de eroi a scazut dar board-ul e la fel (combine)
        total_before = before.board_count + before.bench_count
        total_after = after.board_count + after.bench_count
        if total_after < total_before - 1 and after.board_count >= before.board_count:
            r = 3.0  # Combine reusit!
            reward += r
            breakdown["hero_combine"] = r

        # ===== PENALITATE: Game over =====
        if after.hp <= 0:
            r = -10.0
            reward += r
            breakdown["game_over"] = r
            log.warning(f"Game over detectat! Total runde supravietuite: {self.rounds_survived}")

        # ===== PENALITATE: Actiune wait excesiv =====
        if action_type == "wait" and before.phase == "planning":
            r = -0.1  # Mica penalitate pentru inactivitate in planning
            reward += r
            breakdown["idle_in_planning"] = r

        # Clamp reward
        reward = max(-10.0, min(10.0, reward))
        self.total_reward += reward

        log.debug(
            f"Reward: {reward:+.2f} | "
            + " | ".join(f"{k}: {v:+.2f}" for k, v in breakdown.items())
        )

        return reward, breakdown

    def record_experience(
        self,
        state_before: Dict,
        action: Dict,
        state_after: Dict,
    ) -> float:
        """
        Inregistreaza o experienta si calculeaza reward-ul.
        Salveaza in knowledge base daca e interesanta (reward extrem).
        """
        reward, breakdown = self.compute_reward(state_before, action, state_after)

        # Genereaza lectia
        lesson = self._generate_lesson(state_before, action, state_after, reward, breakdown)

        exp = Experience(
            state_before=state_before,
            action=action,
            state_after=state_after,
            reward=reward,
            reward_breakdown=breakdown,
            lesson=lesson,
        )
        self.episode_experiences.append(exp)

        # Salveaza in KB experientele importante (reward > 1 sau < -1)
        if abs(reward) >= 1.0:
            self.kb.add_experience(
                game_name=self.game_name,
                situation=state_before,
                action={**action, "reward": reward, "lesson": lesson},
                outcome="succes" if reward > 0 else "esec",
            )

        return reward

    def get_recent_context(self, n: int = 5) -> str:
        """
        Returneaza ultimele N experiente ca text pentru contextul LLM.
        Ajuta Claude sa invete din greseli recente.
        """
        if not self.episode_experiences:
            return ""

        recent = self.episode_experiences[-n:]
        lines = ["=== Experiente recente (trial & error) ==="]

        for exp in recent:
            sign = "+" if exp.reward > 0 else ""
            lines.append(
                f"• Actiune: {exp.action.get('action')} | "
                f"Reward: {sign}{exp.reward:.1f} | "
                f"Lectie: {exp.lesson}"
            )

        lines.append(f"Total reward episod: {self.total_reward:+.1f}")
        lines.append(f"Runde supravietuite: {self.rounds_survived}")
        return "\n".join(lines)

    def get_episode_summary(self) -> Dict:
        """Rezuma episodul curent."""
        return {
            "total_reward": self.total_reward,
            "rounds_survived": self.rounds_survived,
            "max_round": self.max_round,
            "experiences": len(self.episode_experiences),
            "positive": sum(1 for e in self.episode_experiences if e.reward > 0),
            "negative": sum(1 for e in self.episode_experiences if e.reward < 0),
        }

    def reset_episode(self):
        """Reseteaza pentru un nou episod (o noua partida)."""
        summary = self.get_episode_summary()
        log.info(
            f"Episod terminat | Reward total: {summary['total_reward']:+.1f} | "
            f"Runde: {summary['rounds_survived']} | "
            f"Exp pozitive: {summary['positive']} | negative: {summary['negative']}"
        )

        # Salveaza rezumatul episodului in KB
        self.kb.add_strategy(
            game_name=self.game_name,
            strategy=(
                f"[Experienta proprie] Runde supravietuite: {summary['rounds_survived']}, "
                f"Reward total: {summary['total_reward']:.1f}. "
                f"Lectii: {self._top_lessons()}"
            ),
            tags=["self-play", f"round-{summary['max_round']}"]
        )

        self.episode_experiences = []
        self.total_reward = 0.0
        self.rounds_survived = 0
        self.max_round = 0
        self.prev_snapshot = None

    def _snap(self, state: Dict) -> GameSnapshot:
        """Converteste state dict in GameSnapshot."""
        return GameSnapshot(
            gold=int(state.get("gold") or 0),
            hp=int(state.get("hp") or 100),
            round_num=int(state.get("round") or 0),
            level=int(state.get("level") or 1),
            board_count=len(state.get("board") or []),
            bench_count=len(state.get("bench") or []),
            phase=str(state.get("phase") or "unknown"),
        )

    def _generate_lesson(
        self,
        before: Dict,
        action: Dict,
        after: Dict,
        reward: float,
        breakdown: Dict,
    ) -> str:
        """Genereaza o lectie scurta din experienta."""
        action_type = action.get("action", "?")
        if reward > 2:
            top_key = max(breakdown, key=breakdown.get, default="")
            return f"'{action_type}' a dat reward mare ({top_key})"
        elif reward < -1:
            top_key = min(breakdown, key=breakdown.get, default="")
            return f"'{action_type}' a dat penalitate ({top_key}) - de evitat"
        else:
            return f"'{action_type}' = reward neutru"

    def _top_lessons(self, n: int = 3) -> str:
        """Cele mai importante lectii din episod."""
        significant = sorted(
            [e for e in self.episode_experiences if abs(e.reward) >= 1.0],
            key=lambda e: abs(e.reward),
            reverse=True,
        )[:n]
        if not significant:
            return "fara lectii majore"
        return "; ".join(e.lesson for e in significant)
