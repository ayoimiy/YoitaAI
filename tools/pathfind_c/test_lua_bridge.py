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


def test_lua_c_compute():
    """Test pf.compute() — the in-memory mod-friendly API with segment classification."""
    random.seed(42)
    failed = 0
    sizes = [(10, 10), (20, 20), (50, 30), (100, 100)]
    CWD = Path(__file__).parent
    TEST_LUA = CWD / "_test_compute_verify.lua"

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
        py_result = pathfind_weighted(world, (sx, sy), (gx, gy))
        py_path = [(x, y) for x, y in py_result] if py_result else None

        # Reference segment classification (matching mode_big.py:223-235)
        py_seg = []
        if py_path:
            floating = [world.is_walkable(p[0], p[1] + 1) for p in py_path]
            long_run = [False] * len(py_path)
            rs = 0
            for i in range(1, len(py_path) + 1):
                flt = floating[i - 1] if i <= len(py_path) else True
                if not flt:
                    if i - 1 - rs >= 10:
                        for j in range(rs, i - 1):
                            long_run[j] = True
                    rs = i
            if len(py_path) - rs >= 10:
                for j in range(rs, len(py_path)):
                    long_run[j] = True
            py_seg = [2 if long_run[i] else (1 if floating[i] else 0) for i in range(len(py_path))]

        # Write input file
        with open(PF_IN, "wb") as f:
            f.write(struct.pack("i", w)); f.write(struct.pack("i", h))
            f.write(struct.pack("i", sx)); f.write(struct.pack("i", sy))
            f.write(struct.pack("i", gx)); f.write(struct.pack("i", gy))
            data = bytearray(w * h)
            for y in range(h):
                for x in range(w):
                    data[y * w + x] = 1 if cells[y][x] else 0
            f.write(data)

        # Write Lua test script that uses compute() and serialises result
        lua_code = f"""local pf = require("pathfind_c")
local fi = io.open([[{str(PF_IN.resolve()).replace(chr(92), '/')}]], "rb")
local function ri()
    local b1,b2,b3,b4 = fi:read(4):byte(1,4)
    return b1+b2*256+b3*65536+b4*16777216
end
local W,H,sx,sy,gx,gy = ri(),ri(),ri(),ri(),ri(),ri()
local data = fi:read(W*H); fi:close()
local r = pf.compute(W, H, data, sx, sy, gx, gy)
if not r or not r.ok then
    print("RESULT: fail")
    os.exit(0)
end
print("RESULT: ok")
print("LEN: " .. r.len)
print("MS: " .. r.ms)
print("PX: " .. table.concat(r.px or {{}}, ","))
print("PY: " .. table.concat(r.py or {{}}, ","))
print("SEG: " .. table.concat(r.seg or {{}}, ","))
"""
        with open(TEST_LUA, "w") as f:
            f.write(lua_code)

        try:
            result = sp.run(
                [LUA_EXE, str(TEST_LUA.resolve())],
                cwd=str(CWD.resolve()),
                timeout=30,
                capture_output=True, text=True,
            )
        except Exception as e:
            print(f"  FAIL test {test_id} ({w}x{h}): subprocess error — {e}")
            failed += 1
            continue

        if result.returncode != 0:
            print(f"  FAIL test {test_id} ({w}x{h}): Lua error\n{result.stderr}")
            failed += 1
            continue

        # Parse output
        lines = result.stdout.strip().split("\n")
        lua_path = None
        lua_seg = None
        lua_len = 0
        lua_ms = 0
        for line in lines:
            if line.startswith("RESULT: fail"):
                lua_path = None
                break
            elif line.startswith("RESULT: ok"):
                pass
            elif line.startswith("LEN: "):
                lua_len = int(line[5:])
            elif line.startswith("MS: "):
                lua_ms = int(line[4:])
            elif line.startswith("PX: "):
                lua_path = [(int(v), 0) for v in line[4:].split(",") if v]
            elif line.startswith("PY: "):
                py_vals = [int(v) for v in line[4:].split(",") if v]
                if lua_path:
                    lua_path = [(lua_path[i][0], py_vals[i]) for i in range(len(py_vals))]
            elif line.startswith("SEG: "):
                lua_seg = [int(v) for v in line[4:].split(",") if v]

        # --- validate ---
        if py_path is None and lua_path is None:
            print(f"  OK  test {test_id} ({w}x{h}): both no path")
        elif py_path is None:
            print(f"  FAIL test {test_id} ({w}x{h}): Python no path, compute() has {lua_len} steps")
            failed += 1
        elif lua_path is None:
            print(f"  FAIL test {test_id} ({w}x{h}): Python {len(py_path)} steps, compute() no path")
            failed += 1
        elif lua_path != py_path:
            print(f"  FAIL test {test_id} ({w}x{h}): paths differ")
            print(f"    compute start={lua_path[0]} end={lua_path[-1]} len={len(lua_path)}")
            print(f"    Py      start={py_path[0]} end={py_path[-1]} len={len(py_path)}")
            failed += 1
        elif lua_seg != py_seg:
            print(f"  FAIL test {test_id} ({w}x{h}): segment classification differs")
            print(f"    compute seg counts: {lua_seg.count(0)}g {lua_seg.count(1)}s {lua_seg.count(2)}l")
            print(f"    Py      seg counts: {py_seg.count(0)}g {py_seg.count(1)}s {py_seg.count(2)}l")
            failed += 1
        else:
            g, s, lng = lua_seg.count(0), lua_seg.count(1), lua_seg.count(2)
            print(f"  OK  test {test_id} ({w}x{h}): {lua_len} steps {lua_ms}ms  seg={g}g/{s}s/{lng}l")

    # Clean up temp file
    if TEST_LUA.exists():
        TEST_LUA.unlink()

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
    print("=" * 55)
    print("  pf.compute() API (in-memory + segment classify)")
    print("=" * 55)
    comp_failed = test_lua_c_compute()
    if comp_failed:
        print(f"\n  {comp_failed} compute() tests FAILED")
    else:
        print(f"\n  ALL {len(sizes)} compute() tests PASSED")

    print()
    total_failed = lua_failed + luc_failed + comp_failed
    if total_failed:
        print(f"{total_failed} TOTAL FAILURES")
        sys.exit(1)
    else:
        print(f"ALL TESTS PASSED (Lua + Lua->C + compute)")
        sys.exit(0)


if __name__ == "__main__":
    main()
