"""
5-level buffered logger (cloned from YoitaAI files/scripts/Log/log.lua)
"""

from datetime import datetime
from enum import IntEnum
import time


class Level(IntEnum):
    DEBUG = 1
    INFO = 2
    WARN = 3
    ERROR = 4
    NONE = 5


class Logger:
    """Buffered logger that flushes to date-stamped files."""

    def __init__(self, global_level=Level.INFO, log_to_file=True,
                 log_dir="", current_pos="", enabled_perf=False):
        self._buffer = []
        self.global_level = global_level
        self.current_level = max(Level.INFO, global_level)
        self.log_to_file = log_to_file
        self.log_dir = log_dir
        self.current_pos = current_pos
        self.current_fore = 0
        self.enabled_perf = enabled_perf
        self._perf_data = {}

    def set_level(self, level):
        self.current_level = max(level, self.global_level)

    def _get_fore(self):
        return " " * max(0, self.current_fore)

    def _timestamp(self):
        return datetime.now().strftime("%H:%M:%S")

    def _level_str(self, level):
        return {Level.DEBUG: "DEBUG", Level.INFO: "INFO",
                Level.WARN: "WARN", Level.ERROR: "ERROR"}.get(level, "UNKNOWN")

    def _write(self, level, message):
        if level < self.current_level:
            return
        entry = f"{self._timestamp()} [{self._level_str(level)}] [{self.current_pos}] {self._get_fore()}{message}"
        self._buffer.append(entry)

    def debug(self, msg):   self._write(Level.DEBUG, msg)
    def info(self, msg):    self._write(Level.INFO, msg)
    def warn(self, msg):    self._write(Level.WARN, msg)
    def error(self, msg):   self._write(Level.ERROR, msg)

    def start(self):
        ts = self._timestamp()
        self._buffer.append(f"\n\n======= Log Start =======\n  Time: {ts}\n")

    def flush(self):
        """Write buffer to date-stamped file, then clear."""
        if not self.log_to_file or not self._buffer:
            return
        self._buffer.append("")
        filename = f"{self.log_dir}log_{datetime.now():%Y-%m-%d}.txt"
        try:
            with open(filename, "a", encoding="utf-8") as f:
                f.write("\n".join(self._buffer))
        except OSError as e:
            print(f"[Logger] write error: {e}")
        self._buffer.clear()

    # ── Performance timing ─────────────────────────
    def start_timer(self, name):
        if not self.enabled_perf:
            return
        entry = self._perf_data.setdefault(name, {"calls": 0, "total": 0.0})
        entry["_start"] = time.perf_counter()
        entry["calls"] += 1

    def end_timer(self, name):
        if not self.enabled_perf or name not in self._perf_data:
            return
        entry = self._perf_data[name]
        entry["total"] += time.perf_counter() - entry.pop("_start", 0)

    def log_performance(self):
        if not self.enabled_perf:
            return
        self.info("=== Performance Report ===")
        for name, d in self._perf_data.items():
            avg = d["total"] / d["calls"] if d["calls"] else 0
            self.info(f"  {name}: calls={d['calls']} total={d['total']:.4f}s avg={avg*1000:.2f}ms")
