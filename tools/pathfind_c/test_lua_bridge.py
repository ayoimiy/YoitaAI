"""
End-to-end test: Lua bridge & Lua->C bridge vs Python Weighted A*.
Run: python tools/pathfind_c/test_lua_bridge.py

Verifies both:
  Pure Lua  (lua_bridge_runner.lua)  → interprets weighted_astar.lua
  Lua->C    (lua_c_runner.lua)       → require("pathfind_c") → C DLL
against the Python reference implementation.
"""
import sys, struct, subprocess as sp
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))

from core.world import GridWorld
from algo.pathfind import pathfind_weighted
import random, time

PF_IN = Path(__file__).parent / "pf_in.bin"
PF_OUT = Path(__file__).parent / "pf_out.bin"
LUA_EXE = "E:/dev/lua5.1.exe"
LUA_RUNNER = Path(__file__).parent / "lua_bridge_runner.lua"
LUA_C_RUNNER = Path(__file__).parent / "lua_c_runner.lua"
CWD = Path(__file__).parent


def run_bridge(label, runner, sizes):
    """Run a bridge and compare against Python reference. Returns failure count."""
    random.seed(42)
    failed = 0

    for test_id, (w, h) in enumerate(sizes, 1):
        cells = [[random.random() > 0.2 for _ in range(w)] for _ in range(h)]
        world = GridWorld(w, h)
        world.cells = cells

        for _ in range(100):
            sx, sy = random.randint(0, w - 1), random.randint(0, h - 1)
            gx, gy = random.randint(0, w - 1), random.randint(0, h - 1)
            if cells[sy][sx] and cells[gy][gx] and abs(sx - gx) + abs(sy - gy) > max(w, h) // 3:
                break

        # --- python reference ---
        t0 = time.perf_counter()
        py_result = pathfind_weighted(world, (sx, sy), (gx, gy))
        py_ms = (time.perf_counter() - t0) * 1000
        py_path = [(x, y) for x, y in py_result] if py_result else None

        # --- write input ---
        with open(PF_IN, "wb") as f:
            f.write(struct.pack("i", w))
            f.write(struct.pack("i", h))
            f.write(struct.pack("i", sx))
            f.write(struct.pack("i", sy))
            f.write(struct.pack("i", gx))
            f.write(struct.pack("i", gy))
            data = bytearray(w * h)
            for y in range(h):
                for x in range(w):
                    data[y * w + x] = 1 if cells[y][x] else 0
            f.write(data)

        # --- run bridge ---
        try:
            sp.run(
                [LUA_EXE, str(runner.resolve()), str(PF_IN.resolve()), str(PF_OUT.resolve())],
                cwd=str(CWD.resolve()),
                timeout=30,
            )
        except Exception as e:
            print(f"  FAIL test {test_id} ({w}x{h}): subprocess error — {e}")
            failed += 1
            continue

        # --- read output ---
        with open(PF_OUT, "rb") as f:
            plen = struct.unpack("i", f.read(4))[0]
            br_ems = struct.unpack("i", f.read(4))[0]
            br_path = None
            if plen > 0:
                px = struct.unpack(f"{plen}i", f.read(4 * plen))
                py = struct.unpack(f"{plen}i", f.read(4 * plen))
                br_path = list(zip(px, py))

        # --- validate ---
        if py_path is None and br_path is None:
            print(f"  OK  test {test_id} ({w}x{h}): both no path")
        elif py_path is None:
            print(f"  FAIL test {test_id} ({w}x{h}): Python no path, bridge {len(br_path)} steps")
            failed += 1
        elif br_path is None:
            print(f"  FAIL test {test_id} ({w}x{h}): Python {len(py_path)} steps, bridge no path")
            failed += 1
        elif br_path != py_path:
            print(f"  FAIL test {test_id} ({w}x{h}): paths differ")
            print(f"    bridge start={br_path[0]} end={br_path[-1]} len={len(br_path)}")
            print(f"    Py     start={py_path[0]} end={py_path[-1]} len={len(py_path)}")
            failed += 1
        else:
            print(f"  OK  test {test_id} ({w}x{h}): {len(br_path)} steps, bridge {br_ems}ms / Py {py_ms:.0f}ms")

    return failed


def main():
    sizes = [(10, 10), (20, 20), (50, 30), (100, 100)]

    print("=" * 55)
    print("  Pure Lua bridge (lua_bridge_runner.lua)")
    print("=" * 55)
    lua_failed = run_bridge("Lua", LUA_RUNNER, sizes)
    if lua_failed:
        print(f"\n  {lua_failed} Lua tests FAILED")
    else:
        print(f"\n  ALL {len(sizes)} Lua tests PASSED")

    print()
    print("=" * 55)
    print("  Lua->C bridge (lua_c_runner.lua -> pathfind_c.dll)")
    print("=" * 55)
    luc_failed = run_bridge("Lua->C", LUA_C_RUNNER, sizes)
    if luc_failed:
        print(f"\n  {luc_failed} Lua->C tests FAILED")
    else:
        print(f"\n  ALL {len(sizes)} Lua->C tests PASSED")

    print()
    total_failed = lua_failed + luc_failed
    if total_failed:
        print(f"{total_failed} TOTAL FAILURES")
        sys.exit(1)
    else:
        print("ALL TESTS PASSED (Lua + Lua->C)")
        sys.exit(0)


if __name__ == "__main__":
    main()
