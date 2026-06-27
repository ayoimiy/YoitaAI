"""
Player state — position and chunk tracking.
"""

from config import WORLD_WIDTH, WORLD_HEIGHT


class Player:
    """A simple player with grid position."""

    def __init__(self, x=None, y=None):
        self.x = x if x is not None else WORLD_WIDTH // 2
        self.y = y if y is not None else WORLD_HEIGHT // 2

    def set_pos(self, x, y):
        self.x = x
        self.y = y

    def pos(self):
        return (self.x, self.y)

    def reset_to_center(self):
        self.x = WORLD_WIDTH // 2
        self.y = WORLD_HEIGHT // 2
