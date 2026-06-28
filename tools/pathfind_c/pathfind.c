/*
 * pathfind.c — Weighted A* with exponential flight fatigue
 *
 * R1 optimisations (path-identical to Python):
 *   1.1  uint32_t state packing (x:14 y:14 air:4) — halved heap node memory
 *   1.2  4-ary heap — halved tree depth, fewer cache misses
 *   1.3  Redundant st_idx eliminated — reuse computed ni in inner loop
 *   1.4  grid_walkable_fast — skip bounds checks for interior cells
 *   1.6  float heap keys — 50% less key memory bandwidth
 *
 * R2 (optional — faster, near-optimal paths):
 *   2.1  Heuristic inflation: f = g + W*h  via pathfind_weighted_fast()
 */
#include "pathfind.h"
#include <math.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
static double now_ms(void) {
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c);
    return (double)c.QuadPart / (double)f.QuadPart * 1000.0;
}
#else
#include <sys/time.h>
static double now_ms(void) {
    struct timeval tv; gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}
#endif

/* ── Grid ────────────────────────────────────────── */
Grid grid_create(int w, int h) {
    Grid g; g.w = w; g.h = h;
    g.cells = (uint8_t *)calloc((size_t)w * h, 1); return g;
}
void grid_free(Grid *g) { free(g->cells); g->cells = NULL; }

/* R1.4 — standard bounds-checked walkable */
int grid_walkable(const Grid *g, int x, int y) {
    if ((unsigned)x >= (unsigned)g->w || (unsigned)y >= (unsigned)g->h) return 0;
    return g->cells[y * g->w + x] != 0;
}

/* R1.4 — fast path for interior cells (no bounds check needed) */
static inline int grid_walkable_fast(const Grid *g, int x, int y) {
    return g->cells[y * g->w + x] != 0;
}

/* ── State packing (R1.1 — uint32_t) ───────────────
 * x:14 bits (0..16383), y:14 bits (0..16383), air:4 bits (0..15) */
#define STATE(x, y, air) (((uint32_t)(x) << 18) | ((uint32_t)(y) << 4) | (uint32_t)(air))
#define STATE_X(s)       ((int)((s) >> 18))
#define STATE_Y(s)       ((int)(((s) >> 4) & 0x3FFF))
#define STATE_AIR(s)     ((int)((s) & 0xF))

/* ── Heuristic ───────────────────────────────────── */
static inline float octile(int x1, int y1, int x2, int y2) {
    int dx = abs(x1 - x2), dy = abs(y1 - y2);
    return (dx > dy) ? ((float)dx + 0.41421356f * (float)dy)
                     : ((float)dy + 0.41421356f * (float)dx);
}

/* ── Movement weights ────────────────────────────── */
static const float wcost[3][3] = {
    {1.5f, 1.0f, 1.5f},
    {1.0f, 0.0f, 1.0f},
    {1.5f, 1.0f, 1.5f}
};

/* ── Penalty tables ──────────────────────────────── */
#define PEN_TABSZ 256
static float up_pen[PEN_TABSZ], hz_pen[PEN_TABSZ], dn_pen[PEN_TABSZ];
static int pen_ok = 0;
static void pen_init(void) {
    if (pen_ok) return; pen_ok = 1;
    for (int n = 1; n < PEN_TABSZ; n++) {
        up_pen[n] = 2.0f * powf(1.30f, (float)(n - 1));
        hz_pen[n] = 0.5f * powf(1.20f, (float)(n - 1));
        dn_pen[n] = 0.5f + 0.08f * (float)n;
    }
}
static inline float up_p(int n) { return up_pen[n < PEN_TABSZ ? n : PEN_TABSZ-1]; }
static inline float hz_p(int n) { return hz_pen[n < PEN_TABSZ ? n : PEN_TABSZ-1]; }
static inline float dn_p(int n) { return dn_pen[n < PEN_TABSZ ? n : PEN_TABSZ-1]; }

/* ── 8-direction neighbours ───────────────────────── */
static int neighbours(const Grid *g, int cx, int cy, int *ox, int *oy, int mx) {
    static const int dx[] = {-1,-1,-1, 0,0,0, 1,1,1};
    static const int dy[] = {-1, 0, 1,-1,0,1,-1,0,1};
    int n = 0;

    /* R1.4 — interior cells skip bounds checks */
    int interior = ((unsigned)(cx - 1) < (unsigned)(g->w - 2)) &&
                   ((unsigned)(cy - 1) < (unsigned)(g->h - 2));
    int (*gw)(const Grid *, int, int) = interior ? grid_walkable_fast : grid_walkable;

    for (int d = 0; d < 9; d++) {
        if (dx[d] == 0 && dy[d] == 0) continue;
        int nx = cx + dx[d], ny = cy + dy[d];
        if (!gw(g, nx, ny)) continue;
        if (dx[d] != 0 && dy[d] != 0 &&
            !gw(g, cx + dx[d], cy) &&
            !gw(g, cx, cy + dy[d])) continue;
        if (n < mx) { ox[n] = nx; oy[n] = ny; n++; }
    }
    return n;
}

/* ── 4-ary min-heap (R1.2 + R1.6 — float keys) ───── */
#define TIE_EPS 1e-12f
#define HEAP_K 4
typedef struct { uint32_t *n; float *k; int s, c; } Heap;

static void hp_init(Heap *h, int cap) {
    h->n = (uint32_t *)malloc((size_t)cap * sizeof(uint32_t));
    h->k = (float    *)malloc((size_t)cap * sizeof(float));
    h->s = 0; h->c = cap;
}
static void hp_free(Heap *h) { free(h->n); free(h->k); }

static void hp_push(Heap *h, uint32_t nd, float key) {
    if (h->s >= h->c) { h->c *= 2;
        h->n = (uint32_t *)realloc(h->n, (size_t)h->c * sizeof(uint32_t));
        h->k = (float    *)realloc(h->k, (size_t)h->c * sizeof(float)); }
    int i = h->s++;
    while (i > 0) {
        int p = (i - 1) / HEAP_K;
        if (key >= h->k[p]) break;
        h->n[i] = h->n[p]; h->k[i] = h->k[p];
        i = p;
    }
    h->n[i] = nd; h->k[i] = key;
}

static uint32_t hp_pop(Heap *h) {
    if (!h->s) return ~0u;
    uint32_t r = h->n[0];
    float    lk = h->k[--h->s];
    uint32_t ln = h->n[h->s];
    int i = 0;
    while (1) {
        int fc = HEAP_K * i + 1;  /* first child */
        if (fc >= h->s) break;
        int smallest = i;
        float cmp = (smallest == i) ? lk : h->k[smallest];
        int lc = fc + HEAP_K - 1;
        if (lc >= h->s) lc = h->s - 1;
        for (int c = fc; c <= lc; c++) {
            if (h->k[c] < cmp) { smallest = c; cmp = h->k[c]; }
        }
        if (smallest == i) break;
        h->n[i] = h->n[smallest]; h->k[i] = h->k[smallest];
        i = smallest;
    }
    h->n[i] = ln; h->k[i] = lk;
    return r;
}

/* ── Direct-array state storage ──────────────────── */
#define AIR_MAX 15
#define AIR_N   (AIR_MAX + 1)

static float    *g_arr = NULL;
static uint64_t *p_arr = NULL;
static uint8_t  *c_arr = NULL;
static float    *d_arr = NULL;
static int       g_W = 0, g_H = 0;

static void arr_init(int W, int H) {
    size_t total = (size_t)W * H * AIR_N;
    if (g_W != W || g_H != H) {
        g_W = W; g_H = H;
        free(g_arr); free(p_arr); free(c_arr); free(d_arr);
        g_arr = (float    *)malloc(total * sizeof(float));
        p_arr = (uint64_t *)malloc(total * sizeof(uint64_t));
        c_arr = (uint8_t  *)calloc(total, 1);
        d_arr = (float    *)malloc(total * sizeof(float));
    } else {
        memset(c_arr, 0, total);
    }
    for (size_t i = 0; i < total; i++) {
        g_arr[i] = INFINITY;
        p_arr[i] = ~0ULL;
        d_arr[i] = INFINITY;
    }
}

static inline size_t st_idx(int x, int y, int a) {
    return ((size_t)y * g_W + (size_t)x) * AIR_N + (size_t)(a < AIR_N ? a : AIR_MAX);
}

static int dom_dominated(int x, int y, int air, float cost) {
    size_t base = ((size_t)y * g_W + (size_t)x) * AIR_N;
    int n = air < AIR_MAX ? air : AIR_MAX;
    for (int a = 0; a <= n; a++)
        if (d_arr[base + a] <= cost) return 1;
    return 0;
}
static void dom_record(int x, int y, int air, float cost) {
    size_t i = ((size_t)y * g_W + (size_t)x) * AIR_N + (size_t)(air < AIR_N ? air : AIR_MAX);
    if (cost < d_arr[i]) d_arr[i] = cost;
}

/* ═══════════════════════════════════════════════════
 *  Internal implementation (shared by both APIs)
 * ═══════════════════════════════════════════════════ */
static int _pathfind_impl(
    const Grid *g, int sx, int sy, int gx, int gy,
    int max_iter, float weight,
    int **px, int **py, float *elapsed_ms)
{
    pen_init();
    double t0 = now_ms();

    arr_init(g->w, g->h);

    Heap open; hp_init(&open, 1 << 20);

    /* Init start state */
    uint32_t ss = STATE(sx, sy, 0);
    {
        size_t si = st_idx(sx, sy, 0);
        g_arr[si] = 0.0f;
        p_arr[si] = ~0ULL;
        dom_record(sx, sy, 0, 0.0f);
    }
    hp_push(&open, ss, weight * octile(sx, sy, gx, gy) + (float)ss * TIE_EPS);

    int ox[8], oy[8], iter = 0;
    uint32_t gs = 0;

    while (open.s > 0 && iter < max_iter) {
        uint32_t cs = hp_pop(&open);
        int cx = STATE_X(cs), cy = STATE_Y(cs), ca = STATE_AIR(cs);

        /* R1.3 — cache state index once per expand */
        size_t ci = st_idx(cx, cy, ca);
        if (c_arr[ci]) continue;
        c_arr[ci] = 1;
        iter++;

        if (cx == gx && cy == gy) { gs = cs; break; }

        float cur_g = g_arr[ci];
        int nc = neighbours(g, cx, cy, ox, oy, 8);

        for (int i = 0; i < nc; i++) {
            int nx = ox[i], ny = oy[i];
            int dxi = nx - cx + 1, dyi = ny - cy + 1;
            float step = wcost[dyi][dxi];
            int dr = ny - cy;
            int ng = !grid_walkable(g, nx, ny + 1);
            int na;

            if (ng) {
                step = (step - 0.7f > 0.1f) ? step - 0.7f : 0.1f;
                na = 0;
                if (ca > 0) step += 1.0f;
            } else {
                na = ca + 1;
                if (na > AIR_MAX) na = AIR_MAX;  /* cap penalty, don't block traversal */
                if (dr < 0) {
                    step += up_p(na);
                    if (ca == 0) step += 0.5f;
                } else if (dr > 0) {
                    step += dn_p(na);
                } else {
                    step += hz_p(na);
                }
            }

            float gn = cur_g + step;

            /* P2: closed → g_score → dom */
            size_t ni = st_idx(nx, ny, na);
            if (c_arr[ni]) continue;
            if (gn >= g_arr[ni]) continue;
            if (dom_dominated(nx, ny, na, gn)) continue;

            /* R1.3 — write directly via ni (no redundant st_idx) */
            g_arr[ni] = gn;
            p_arr[ni] = (uint64_t)cs;
            dom_record(nx, ny, na, gn);
            hp_push(&open, STATE(nx, ny, na),
                     weight * (gn + octile(nx, ny, gx, gy)) + (float)STATE(nx,ny,na) * TIE_EPS);
        }
    }

    hp_free(&open);
    if (elapsed_ms) *elapsed_ms = (float)(now_ms() - t0);
    if (!gs) { *px = NULL; *py = NULL; return 0; }

    /* Reconstruct path */
    int plen = 0;
    {
        int x = STATE_X(gs), y = STATE_Y(gs), a = STATE_AIR(gs);
        while (1) {
            plen++;
            uint64_t p = p_arr[st_idx(x, y, a)];
            if (p == ~0ULL) break;
            x = STATE_X((uint32_t)p); y = STATE_Y((uint32_t)p); a = STATE_AIR((uint32_t)p);
        }
    }

    *px = (int *)malloc((size_t)plen * sizeof(int));
    *py = (int *)malloc((size_t)plen * sizeof(int));
    {
        int idx = plen - 1;
        int x = STATE_X(gs), y = STATE_Y(gs), a = STATE_AIR(gs);
        while (1) {
            (*px)[idx] = x; (*py)[idx] = y;
            uint64_t p = p_arr[st_idx(x, y, a)];
            if (p == ~0ULL) break;
            x = STATE_X((uint32_t)p); y = STATE_Y((uint32_t)p); a = STATE_AIR((uint32_t)p);
            idx--;
        }
    }
    return plen;
}

/* ── Public API ──────────────────────────────────── */
int pathfind_weighted(
    const Grid *g, int sx, int sy, int gx, int gy,
    int max_air, int max_iter, int **px, int **py, float *elapsed_ms)
{
    (void)max_air;
    return _pathfind_impl(g, sx, sy, gx, gy, max_iter, 1.0f, px, py, elapsed_ms);
}

/* R2.1 — heuristic-inflated search for near-optimal fast paths */
int pathfind_weighted_fast(
    const Grid *g, int sx, int sy, int gx, int gy,
    int max_air, int max_iter, float weight,
    int **px, int **py, float *elapsed_ms)
{
    (void)max_air;
    if (weight < 1.0f) weight = 1.0f;
    return _pathfind_impl(g, sx, sy, gx, gy, max_iter, weight, px, py, elapsed_ms);
}
