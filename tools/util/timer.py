"""
Frame-countdown timer (cloned from YoitaAI files/scripts/utils/SetTimeOut.lua).

Each call to tick() decrements all pending timers;
when a timer reaches 0 its callback is fired (once).
"""


class FrameTimer:
    """A simple frame-countdown task scheduler."""

    def __init__(self):
        self._tasks = []  # list of [func, remaining_frames, args_tuple]

    def add(self, func, frames, *args):
        """Schedule `func(*args)` to run after `frames` ticks."""
        self._tasks.append([func, frames, args])

    def tick(self):
        """Decrement all timers and fire any that have expired."""
        fired_indices = []
        for i, task in enumerate(self._tasks):
            if task[1] > 0:
                task[1] -= 1
            else:
                task[0](*task[2])
                fired_indices.append(i)

        # Remove in reverse order so indices remain valid
        for i in reversed(fired_indices):
            self._tasks.pop(i)
