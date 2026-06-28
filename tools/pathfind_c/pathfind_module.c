/*
 * pathfind_module.c — Lua 5.1 C module: pathfind_c.find(infile, outfile)
 *
 * Build:
 *   gcc -O3 -shared -o pathfind_c.dll pathfind_module.c pathfind.c -I. -L. -llua51
 *
 * The resulting DLL can be loaded from Lua with:
 *   local pf = require("pathfind_c")
 *   local len, ms = pf.find("pf_in.bin", "pf_out.bin")
 */
#include "pathfind.h"
#include "lua_api.h"

#include <stdio.h>
#include <stdlib.h>

/* ── Read pf_in.bin, run pathfinding, write pf_out.bin ── */
static int l_find(lua_State *L) {
    const char *infile  = luaL_checklstring(L, 1, NULL);
    const char *outfile = luaL_checklstring(L, 2, NULL);

    /* ── Read input ── */
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
        grid_free(&g);
        fclose(fi);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }
    fclose(fi);

    /* ── Run pathfinding ── */
    int *px = NULL, *py = NULL, len;
    float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 2000000, &px, &py, &ms);
    int ems = (int)(ms + 0.5f);

    /* ── Write output ── */
    FILE *fo = fopen(outfile, "wb");
    if (!fo) {
        grid_free(&g);
        free(px); free(py);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        return 2;
    }
    fwrite(&len, 4, 1, fo);
    fwrite(&ems, 4, 1, fo);
    if (len > 0) {
        fwrite(px, 4, (size_t)len, fo);
        fwrite(py, 4, (size_t)len, fo);
        free(px); free(py);
    }
    fclose(fo);
    grid_free(&g);

    lua_pushinteger(L, len);
    lua_pushinteger(L, ems);
    return 2;

bad_input:
    fclose(fi);
    lua_pushinteger(L, 0);
    lua_pushinteger(L, 0);
    return 2;
}

/* ── Module registration ───────────────────────────── */
static const luaL_Reg pathfind_c_lib[] = {
    {"find", l_find},
    {NULL, NULL}
};

int luaopen_pathfind_c(lua_State *L) {
    luaL_register(L, "pathfind_c", pathfind_c_lib);
    return 1;
}
