/*
 * pathfind_module.c — Lua 5.1 C module for Noita mod pathfinding
 *
 * Build:
 *   gcc -O3 -shared -o pathfind_c.dll pathfind_module.c pathfind.c -I. -L. -llua51
 *
 * Usage from Lua:
 *   local pf = require("pathfind_c")
 *
 *   -- Memory API (for mods):
 *   local r = pf.compute(w, h, data_str, sx, sy, gx, gy)
 *   -- r.px[i], r.py[i], r.seg[i] (i=1-indexed), r.len, r.ms, r.ok
 *
 *   -- File API (for offline testing):
 *   local len, ms = pf.find("pf_in.bin", "pf_out.bin")
 */
#include "pathfind.h"
#include "lua_api.h"

#include <stdio.h>
#include <stdlib.h>

/* ═══════════════════════════════════════════════════════════════
 *  Segment classification constants
 * ═══════════════════════════════════════════════════════════════ */
#define SEG_GROUND       0   /* on solid ground — render as RED   */
#define SEG_SHORT_FLOAT  1   /* airborne < 10 steps — GOLD       */
#define SEG_LONG_FLOAT   2   /* airborne >= 10 steps — BLUE      */
#define LONG_FLOAT_MIN  10   /* threshold for long-float segment */

/* ═══════════════════════════════════════════════════════════════
 *  compute(w, h, data_str, sx, sy, gx, gy) -> result table
 *
 *  data_str: binary string, one byte per cell (0=wall, non-zero=walkable)
 *  Returns a Lua table or nil on error.
 * ═══════════════════════════════════════════════════════════════ */
static int l_compute(lua_State *L) {
    int w  = (int)luaL_checkinteger(L, 1);
    int h  = (int)luaL_checkinteger(L, 2);
    size_t data_len;
    const char *data = luaL_checklstring(L, 3, &data_len);
    int sx = (int)luaL_checkinteger(L, 4);
    int sy = (int)luaL_checkinteger(L, 5);
    int gx = (int)luaL_checkinteger(L, 6);
    int gy = (int)luaL_checkinteger(L, 7);

    /* Validate */
    if (w <= 0 || h <= 0 || data_len < (size_t)w * h) {
        lua_pushnil(L);
        lua_pushstring(L, "bad dimensions or data too short");
        return 2;
    }
    if (sx < 0 || sx >= w || sy < 0 || sy >= h ||
        gx < 0 || gx >= w || gy < 0 || gy >= h) {
        lua_pushnil(L);
        lua_pushstring(L, "start or goal out of bounds");
        return 2;
    }

    /* Build grid — data is const but grid_walkable only reads */
    Grid g;
    g.w = w; g.h = h;
    g.cells = (uint8_t *)data;

    /* Check start/goal are walkable */
    if (!grid_walkable(&g, sx, sy) || !grid_walkable(&g, gx, gy)) {
        lua_pushnil(L);
        lua_pushstring(L, "start or goal not walkable");
        return 2;
    }

    /* ── Run pathfinding ── */
    int *px = NULL, *py = NULL, len;
    float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 2000000, &px, &py, &ms);
    int ems = (int)(ms + 0.5f);

    if (!len) {
        lua_pushnil(L);
        lua_pushstring(L, "no path found");
        return 2;
    }

    /* ── Segment classification ──
     * floating[i]: true if cell-below(i) is walkable (i.e. in the air)
     * long_run[i]: true if part of a contiguous airborne segment >= LONG_FLOAT_MIN
     */
    int *floating = (int *)malloc((size_t)len * sizeof(int));
    int *long_run = (int *)calloc((size_t)len, sizeof(int));

    for (int i = 0; i < len; i++) {
        floating[i] = grid_walkable(&g, px[i], py[i] + 1);
    }

    /* Scan for contiguous floating segments */
    int run_start = 0;
    for (int i = 0; i < len; i++) {
        if (!floating[i]) {
            /* Ground hit — close the previous floating run */
            if (i - run_start >= LONG_FLOAT_MIN) {
                for (int j = run_start; j < i; j++) long_run[j] = 1;
            }
            run_start = i + 1;
        }
    }
    /* Handle trailing floating run */
    if (len - run_start >= LONG_FLOAT_MIN) {
        for (int j = run_start; j < len; j++) long_run[j] = 1;
    }

    /* ── Build return table ── */
    lua_createtable(L, 0, 6);

    /* px[i] — 1-indexed Lua array */
    lua_createtable(L, len, 0);
    for (int i = 0; i < len; i++) {
        lua_pushinteger(L, px[i]);
        lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "px");

    /* py[i] — 1-indexed Lua array */
    lua_createtable(L, len, 0);
    for (int i = 0; i < len; i++) {
        lua_pushinteger(L, py[i]);
        lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "py");

    /* seg[i] — 1-indexed Lua array (0=ground, 1=short_float, 2=long_float) */
    lua_createtable(L, len, 0);
    for (int i = 0; i < len; i++) {
        int t = floating[i] ? (long_run[i] ? SEG_LONG_FLOAT : SEG_SHORT_FLOAT) : SEG_GROUND;
        lua_pushinteger(L, t);
        lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "seg");

    lua_pushinteger(L, len);
    lua_setfield(L, -2, "len");

    lua_pushinteger(L, ems);
    lua_setfield(L, -2, "ms");

    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "ok");

    free(px); free(py);
    free(floating); free(long_run);

    return 1;
}

/* ── find (file-based, kept for backward compatibility) ── */
static int l_find(lua_State *L) {
    const char *infile  = luaL_checklstring(L, 1, NULL);
    const char *outfile = luaL_checklstring(L, 2, NULL);

    FILE *fi = fopen(infile, "rb");
    if (!fi) {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }

    int w, h, sx, sy, gx, gy;
    if (fread(&w,  4, 1, fi) != 1) goto bad_input;
    if (fread(&h,  4, 1, fi) != 1) goto bad_input;
    if (fread(&sx, 4, 1, fi) != 1) goto bad_input;
    if (fread(&sy, 4, 1, fi) != 1) goto bad_input;
    if (fread(&gx, 4, 1, fi) != 1) goto bad_input;
    if (fread(&gy, 4, 1, fi) != 1) goto bad_input;

    Grid g = grid_create(w, h);
    if (fread(g.cells, 1, (size_t)w * h, fi) != (size_t)w * h) {
        grid_free(&g); fclose(fi);
        lua_pushinteger(L, 0); lua_pushinteger(L, 0);
        return 2;
    }
    fclose(fi);

    int *px = NULL, *py = NULL, len;
    float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 2000000, &px, &py, &ms);
    int ems = (int)(ms + 0.5f);

    FILE *fo = fopen(outfile, "wb");
    if (!fo) { grid_free(&g); free(px); free(py);
        lua_pushinteger(L, 0); lua_pushinteger(L, 0); return 2; }
    fwrite(&len, 4, 1, fo);
    fwrite(&ems, 4, 1, fo);
    if (len > 0) { fwrite(px, 4, (size_t)len, fo); fwrite(py, 4, (size_t)len, fo); free(px); free(py); }
    fclose(fo);
    grid_free(&g);

    lua_pushinteger(L, len);
    lua_pushinteger(L, ems);
    return 2;

bad_input:
    fclose(fi);
    lua_pushinteger(L, 0); lua_pushinteger(L, 0);
    return 2;
}

/* ── Module registration ───────────────────────────── */
static const luaL_Reg pathfind_c_lib[] = {
    {"compute", l_compute},
    {"find",    l_find},
    {NULL, NULL}
};

int luaopen_pathfind_c(lua_State *L) {
    luaL_register(L, "pathfind_c", pathfind_c_lib);
    return 1;
}
