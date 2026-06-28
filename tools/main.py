"""
Grid Explorer — cave pathfinding visualisation tool.

Usage: python main.py [mode]
  big    — 1000×1000 large-grid instant pathfinding (default)
  small  — 20×20 small-grid animated step-by-step pathfinding

The launcher (launcher.bat) passes the mode automatically.
"""

import sys


def main():
    mode = sys.argv[1].lower() if len(sys.argv) > 1 else "big"

    if mode == "small":
        from mode_small import main as run
    else:
        # Default: big mode
        from mode_big import main as run

    run()


if __name__ == "__main__":
    main()
