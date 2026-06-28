/*
 * lua_api.h — Minimal Lua 5.1 C API declarations
 * Only the types and functions needed by pathfind_module.c.
 * Compatible with lua51.dll / lua5.1.dll (LuaBinaries 5.1.4 MSVC build).
 */
#ifndef LUA_API_H
#define LUA_API_H

#include <stddef.h>   /* size_t */
#include <stdarg.h>   /* va_list */

/* ── Types ─────────────────────────────────────────── */
typedef struct lua_State lua_State;
typedef double          lua_Number;
typedef ptrdiff_t       lua_Integer;

/* Function registration */
typedef struct luaL_Reg {
    const char *name;
    int       (*func)(lua_State *L);
} luaL_Reg;

/* ── State manipulation ────────────────────────────── */
lua_State  *luaL_newstate(void);
void        lua_close(lua_State *L);
void        luaL_openlibs(lua_State *L);

/* ── Stack access ──────────────────────────────────── */
int         lua_gettop(lua_State *L);
void        lua_settop(lua_State *L, int idx);
void        lua_pushvalue(lua_State *L, int idx);
void        lua_remove(lua_State *L, int idx);
void        lua_insert(lua_State *L, int idx);
void        lua_replace(lua_State *L, int idx);
int         lua_checkstack(lua_State *L, int sz);
int         lua_type(lua_State *L, int idx);
const char *lua_typename(lua_State *L, int tp);

/* ── Push functions ────────────────────────────────── */
void        lua_pushnil(lua_State *L);
void        lua_pushnumber(lua_State *L, lua_Number n);
void        lua_pushinteger(lua_State *L, lua_Integer n);
void        lua_pushlstring(lua_State *L, const char *s, size_t len);
void        lua_pushstring(lua_State *L, const char *s);
const char *lua_pushfstring(lua_State *L, const char *fmt, ...);
const char *lua_pushvfstring(lua_State *L, const char *fmt, va_list ap);
void        lua_pushcclosure(lua_State *L, int (*fn)(lua_State *), int n);
void        lua_pushboolean(lua_State *L, int b);

/* ── Get functions ─────────────────────────────────── */
lua_Number       lua_tonumber(lua_State *L, int idx);
lua_Integer      lua_tointeger(lua_State *L, int idx);
int              lua_toboolean(lua_State *L, int idx);
const char      *lua_tolstring(lua_State *L, int idx, size_t *len);
size_t           lua_objlen(lua_State *L, int idx);

/* ── Table manipulation ────────────────────────────── */
void  lua_createtable(lua_State *L, int narr, int nrec);
void  lua_gettable(lua_State *L, int idx);
void  lua_settable(lua_State *L, int idx);
void  lua_getfield(lua_State *L, int idx, const char *k);
void  lua_setfield(lua_State *L, int idx, const char *k);
void  lua_rawgeti(lua_State *L, int idx, int n);
void  lua_rawseti(lua_State *L, int idx, int n);

/* ── Convenience ───────────────────────────────────── */
void        luaL_register(lua_State *L, const char *libname, const luaL_Reg *l);
const char *luaL_checklstring(lua_State *L, int narg, size_t *len);
lua_Integer luaL_checkinteger(lua_State *L, int narg);
int         luaL_error(lua_State *L, const char *fmt, ...);
int         luaL_callmeta(lua_State *L, int obj, const char *e);

/* ── Constants ─────────────────────────────────────── */
#define LUA_TNIL              0
#define LUA_TBOOLEAN          1
#define LUA_TNUMBER           3
#define LUA_TSTRING           4
#define LUA_TTABLE            5
#define LUA_TFUNCTION         6

#define LUA_MINSTACK 20
#define LUA_REGISTRYINDEX (-10000)
#define LUA_GLOBALSINDEX  (-10002)

#endif /* LUA_API_H */
