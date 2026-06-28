/*
 * pathfind.c — Weighted A* with exponential flight fatigue
 * Uses direct-indexed arrays (no hash collisions) for deterministic results.
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
int  grid_walkable(const Grid *g, int x, int y) {
    if ((unsigned)x >= (unsigned)g->w || (unsigned)y >= (unsigned)g->h) return 0;
    return g->cells[y * g->w + x] != 0;
}

/* ── State packing ───────────────────────────────── */
#define STATE(x, y, air) (((uint64_t)(x) << 32) | ((uint64_t)(y) << 16) | (uint64_t)(air))
#define STATE_X(s)       ((int)((s) >> 32))
#define STATE_Y(s)       ((int)(((s) >> 16) & 0xFFFF))
#define STATE_AIR(s)     ((int)((s) & 0xFFFF))

/* ── Heuristic ───────────────────────────────────── */
static inline float octile(int x1, int y1, int x2, int y2) {
    int dx = abs(x1 - x2), dy = abs(y1 - y2);
    return (dx > dy) ? (dx + 0.41421356f * dy) : (dy + 0.41421356f * dx);
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

/* ── 8-direction neighbours (Python order) ────────── */
static int neighbours(const Grid *g, int cx, int cy, int *ox, int *oy, int mx) {
    static const int dx[] = {-1,-1,-1, 0,0,0, 1,1,1};
    static const int dy[] = {-1, 0, 1,-1,0,1,-1,0,1};
    int n = 0;
    for (int d = 0; d < 9; d++) {
        if (dx[d] == 0 && dy[d] == 0) continue;
        int nx = cx + dx[d], ny = cy + dy[d];
        if (!grid_walkable(g, nx, ny)) continue;
        if (dx[d] != 0 && dy[d] != 0 &&
            !grid_walkable(g, cx + dx[d], cy) &&
            !grid_walkable(g, cx, cy + dy[d])) continue;
        if (n < mx) { ox[n] = nx; oy[n] = ny; n++; }
    }
    return n;
}

/* ── Min-heap with deterministic tie-breaking ───────
 * Key format: double = f_score + state * 1e-12
 * When f-scores are equal, lower (x,y,air) wins.
 * This matches Python's tuple-comparison tie-breaking. */
#define TIE_EPS 1e-12
typedef struct { uint64_t *n; double *k; int s, c; } Heap;
static void hp_init(Heap *h, int cap) {
    h->n = malloc((size_t)cap * 8); h->k = malloc((size_t)cap * 8);
    h->s = 0; h->c = cap;
}
static void hp_free(Heap *h) { free(h->n); free(h->k); }
static void hp_push(Heap *h, uint64_t nd, double key) {
    if (h->s >= h->c) { h->c *= 2;
        h->n = realloc(h->n, (size_t)h->c * 8);
        h->k = realloc(h->k, (size_t)h->c * 8); }
    int i = h->s++;
    while (i > 0) { int p = (i-1)/2; if (key >= h->k[p]) break;
        h->n[i]=h->n[p]; h->k[i]=h->k[p]; i = p; }
    h->n[i] = nd; h->k[i] = key;
}
static uint64_t hp_pop(Heap *h) {
    if (!h->s) return ~0ULL;
    uint64_t r = h->n[0];
    double lk = h->k[--h->s];
    uint64_t ln = h->n[h->s];
    int i = 0;
    while (1) {
        int l = 2*i+1, ri = l+1, smallest = i;
        if (l < h->s) {
            double cmp = (smallest == i) ? lk : h->k[smallest];
            if (h->k[l] < cmp) smallest = l;
        }
        if (ri < h->s) {
            double cmp = (smallest == i) ? lk : h->k[smallest];
            if (h->k[ri] < cmp) smallest = ri;
        }
        if (smallest == i) break;
        h->n[i] = h->n[smallest]; h->k[i] = h->k[smallest];
        i = smallest;
    }
    h->n[i] = ln; h->k[i] = lk;
    return r;
}

/* ── Direct-array state storage (no collisions) ──── */
#define AIR_MAX 15
#define AIR_N   (AIR_MAX + 1)   /* 16 */

static float    *g_arr = NULL;   /* g_score[state] */
static uint64_t *p_arr = NULL;   /* parent[state]  */
static uint8_t  *c_arr = NULL;   /* closed[state]  */
static float    *d_arr = NULL;   /* dom[(x,y)*AIR_N + air] */
static int       g_W = 0, g_H = 0;

static void arr_init(int W, int H) {
    size_t total = (size_t)W * H * AIR_N;
    g_W = W; g_H = H;
    free(g_arr); free(p_arr); free(c_arr); free(d_arr);
    g_arr = (float    *)malloc(total * sizeof(float));
    p_arr = (uint64_t *)malloc(total * sizeof(uint64_t));
    c_arr = (uint8_t  *)calloc(total, 1);
    d_arr = (float    *)malloc(total * sizeof(float));
    for (size_t i = 0; i < total; i++) {
        g_arr[i] = INFINITY;
        p_arr[i] = ~0ULL;
        d_arr[i] = INFINITY;
    }
}

static inline size_t st_idx(int x, int y, int a) {
    return ((size_t)y * g_W + (size_t)x) * AIR_N + (size_t)(a < AIR_N ? a : AIR_MAX);
}

#define G_GET(x,y,a)  g_arr[st_idx(x,y,a)]
#define G_SET(x,y,a,v) g_arr[st_idx(x,y,a)] = (v)
#define P_GET(x,y,a)  p_arr[st_idx(x,y,a)]
#define P_SET(x,y,a,v) p_arr[st_idx(x,y,a)] = (v)
#define C_TEST(x,y,a) c_arr[st_idx(x,y,a)]
#define C_SET(x,y,a)  c_arr[st_idx(x,y,a)] = 1

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
 *  pathfind_weighted
 * ═══════════════════════════════════════════════════ */
int pathfind_weighted(
    const Grid *g, int sx, int sy, int gx, int gy,
    int max_air, int max_iter, int **px, int **py, float *elapsed_ms)
{
    (void)max_air;
    pen_init();
    double t0 = now_ms();

    arr_init(g->w, g->h);

    Heap open; hp_init(&open, 65536);

    uint64_t ss = STATE(sx, sy, 0);
    G_SET(sx, sy, 0, 0.0f);
    P_SET(sx, sy, 0, ~0ULL);
    dom_record(sx, sy, 0, 0.0f);
    hp_push(&open, ss, (double)octile(sx, sy, gx, gy) + ss * TIE_EPS);

    int ox[8], oy[8], iter = 0;
    uint64_t gs = 0;

    while (open.s > 0 && iter < max_iter) {
        uint64_t cs = hp_pop(&open);
        int cx = STATE_X(cs), cy = STATE_Y(cs), ca = STATE_AIR(cs);
        if (C_TEST(cx, cy, ca)) continue;
        C_SET(cx, cy, ca);
        iter++;

        if (cx == gx && cy == gy) { gs = cs; break; }

        int nc = neighbours(g, cx, cy, ox, oy, 8);

        for (int i = 0; i < nc; i++) {
            int nx = ox[i], ny = oy[i];
            int dxi = nx - cx + 1, dyi = ny - cy + 1;
            float step = wcost[dyi][dxi];
            int ng = !grid_walkable(g, nx, ny + 1);
            int na;

            int dr = ny - cy;

            if (ng) {
                /* ── Solid ground ── */
                step = (step - 0.7f > 0.1f) ? step - 0.7f : 0.1f;
                na = 0;
                if (ca > 0) step += 1.0f;  /* landing tax */
            } else {
                /* ── In the air ── */
                na = ca + 1;
                if (na > AIR_MAX) continue;  /* _MAX_AIR cap */
                if (dr < 0) {
                    step += up_p(na);
                    if (ca == 0) step += 0.5f;  /* takeoff tax */
                } else if (dr > 0) {
                    step += dn_p(na);
                } else {
                    step += hz_p(na);
                }
            }

            float gn = G_GET(cx, cy, ca) + step;

            if (dom_dominated(nx, ny, na, gn)) continue;

            if (C_TEST(nx, ny, na)) continue;

            float old_g = G_GET(nx, ny, na);
            if (gn >= old_g) continue;

            G_SET(nx, ny, na, gn);
            P_SET(nx, ny, na, cs);
            dom_record(nx, ny, na, gn);
            hp_push(&open, STATE(nx, ny, na),
                     (double)(gn + octile(nx, ny, gx, gy)) + STATE(nx,ny,na) * TIE_EPS);
        }
    }

    hp_free(&open);
    if (elapsed_ms) *elapsed_ms = (float)(now_ms() - t0);
    if (!gs) { *px = NULL; *py = NULL; return 0; }

    /* Reconstruct */
    int plen = 0;
    {
        int x = STATE_X(gs), y = STATE_Y(gs), a = STATE_AIR(gs);
        while (1) {
            plen++;
            uint64_t p = P_GET(x, y, a);
            if (p == ~0ULL) break;
            x = STATE_X(p); y = STATE_Y(p); a = STATE_AIR(p);
        }
    }

    *px = (int *)malloc((size_t)plen * sizeof(int));
    *py = (int *)malloc((size_t)plen * sizeof(int));
    {
        int idx = plen - 1;
        int x = STATE_X(gs), y = STATE_Y(gs), a = STATE_AIR(gs);
        while (1) {
            (*px)[idx] = x; (*py)[idx] = y;
            uint64_t p = P_GET(x, y, a);
            if (p == ~0ULL) break;
            x = STATE_X(p); y = STATE_Y(p); a = STATE_AIR(p);
            idx--;
        }
    }
    return plen;
}
