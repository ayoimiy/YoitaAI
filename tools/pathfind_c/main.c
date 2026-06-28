/*
 * main.c — test harness for pathfind_weighted
 *
 * Build:  gcc -O3 -o pathfind_test.exe pathfind.c main.c -lm
 * Run:    pathfind_test [quick|bench|big|huge|all]
 */
#include "pathfind.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── Map generation (random walk cave) ───────────── */
static void gen_cave(Grid *g, float intensity, unsigned seed) {
    srand(seed);
    int w = g->w, h = g->h;
    int cx = w/2, cy = h/2;
    memset(g->cells, 0, (size_t)w * h);
    for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
            if (cx+dx>=0 && cx+dx<w && cy+dy>=0 && cy+dy<h)
                g->cells[(cy+dy)*w + (cx+dx)] = 1;

    int steps_total = (int)(w * h * 0.35 * intensity);
    float branch_chance = 0.025f * intensity;
    int max_walkers = 2 + (int)(intensity * 6);
    int bloat_limit = 5;

    int *wx = (int *)malloc((size_t)max_walkers * sizeof(int));
    int *wy = (int *)malloc((size_t)max_walkers * sizeof(int));
    int nw = 1; wx[0] = cx; wy[0] = cy;
    int dirs[4][2] = {{0,-1},{0,1},{-1,0},{1,0}};
    int steps = 0;

    while (nw > 0 && steps < steps_total) {
        int wi = rand() % nw;
        int sx = wx[wi], sy = wy[wi];
        for (int d = 0; d < 4; d++) {
            int r = rand()%4; int t0=dirs[d][0]; dirs[d][0]=dirs[r][0]; dirs[r][0]=t0;
            int t1=dirs[d][1]; dirs[d][1]=dirs[r][1]; dirs[r][1]=t1;
        }
        int moved = 0;
        for (int d = 0; d < 4; d++) {
            int nx = sx+dirs[d][0], ny = sy+dirs[d][1];
            if (nx<=2 || nx>=w-3 || ny<=2 || ny>=h-3) continue;
            int on = 0;
            if (g->cells[(ny-1)*w+nx]) on++;
            if (g->cells[(ny+1)*w+nx]) on++;
            if (g->cells[ny*w+nx-1]) on++;
            if (g->cells[ny*w+nx+1]) on++;
            if (on >= bloat_limit) continue;
            g->cells[ny*w+nx] = 1;
            wx[wi]=nx; wy[wi]=ny; moved=1; break;
        }
        if (!moved) { wx[wi]=wx[nw-1]; wy[wi]=wy[nw-1]; nw--; continue; }
        steps++;
        if ((float)rand()/RAND_MAX < branch_chance && nw < max_walkers)
            { wx[nw]=sx; wy[nw]=sy; nw++; }
        if (nw>1 && (float)rand()/RAND_MAX < 0.15f)
            { int ri=rand()%nw; wx[ri]=wx[nw-1]; wy[ri]=wy[nw-1]; nw--; }
    }

    /* Cleanup */
    for (int y=1; y<h-1; y++)
        for (int x=1; x<w-1; x++) {
            if (!g->cells[y*w+x]) continue;
            int n = 0;
            if (g->cells[(y-1)*w+x]) n++;
            if (g->cells[(y+1)*w+x]) n++;
            if (g->cells[y*w+x-1]) n++;
            if (g->cells[y*w+x+1]) n++;
            if (n <= 1) g->cells[y*w+x] = 0;
        }
    free(wx); free(wy);
}

/* ── BFS to find furthest connected cell ─────────── */
static void find_endpoints(Grid *g, int *sx, int *sy, int *gx, int *gy) {
    int w = g->w, h = g->h;
    int cx = w/2, cy = h/2;

    /* Find walkable start near centre */
    *sx = cx; *sy = cy;
    if (!grid_walkable(g, cx, cy)) {
        for (int d = 1; d < w/2; d++)
            for (int dy = -d; dy <= d; dy++)
                for (int dx = -d; dx <= d; dx++)
                    if (grid_walkable(g, cx+dx, cy+dy))
                        { *sx=cx+dx; *sy=cy+dy; d=w; break; }
    }

    /* Simple BFS to find farthest cell */
    int *qx = (int *)malloc((size_t)w * h * sizeof(int));
    int *qy = (int *)malloc((size_t)w * h * sizeof(int));
    char *vis = (char *)calloc((size_t)w * h, 1);
    int head = 0, tail = 0;
    qx[tail] = *sx; qy[tail] = *sy; tail++;
    vis[(*sy)*w + (*sx)] = 1;

    int last_x = *sx, last_y = *sy;
    int dir4[4][2] = {{-1,0},{1,0},{0,-1},{0,1}};

    while (head < tail) {
        int x = qx[head], y = qy[head]; head++;
        last_x = x; last_y = y;
        for (int d = 0; d < 4; d++) {
            int nx = x+dir4[d][0], ny = y+dir4[d][1];
            if ((unsigned)nx >= (unsigned)w || (unsigned)ny >= (unsigned)h) continue;
            if (!grid_walkable(g, nx, ny) || vis[ny*w+nx]) continue;
            vis[ny*w+nx] = 1;
            qx[tail] = nx; qy[tail] = ny; tail++;
        }
    }
    *gx = last_x; *gy = last_y;

    free(qx); free(qy); free(vis);
}

/* ── Path stats ──────────────────────────────────── */
static void path_stats(Grid *g, int *px, int *py, int len) {
    int gnd = 0, up = 0, air = 0, lf = 0, run = 0;
    for (int i = 0; i < len; i++) {
        int og = !grid_walkable(g, px[i], py[i] + 1);
        if (og) { gnd++; if (run>=10) lf+=run; run=0; }
        else    { air++; run++; }
        if (i>0 && py[i] < py[i-1]) up++;
    }
    if (run>=10) lf+=run;
    printf("  %d steps  ground=%.0f%%  up=%d  long_float=%d\n",
           len, len?100.0f*gnd/len:0, up, lf);
}

/* ── Quick test ──────────────────────────────────── */
static void test_quick(void) {
    printf("=== Quick (32x32) ===\n");
    Grid g = grid_create(32, 32);
    gen_cave(&g, 1.5f, 42u);
    int sx, sy, gx, gy;
    find_endpoints(&g, &sx, &sy, &gx, &gy);
    printf("Start=(%d,%d) Goal=(%d,%d)\n", sx, sy, gx, gy);

    int *px, *py, len; float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 200000, &px, &py, &ms);
    printf("Weighted: %d nodes, %.1fms\n", len, ms);
    if (len) { path_stats(&g, px, py, len); free(px); free(py); }
    grid_free(&g);
}

/* ── Benchmark ───────────────────────────────────── */
static void test_benchmark(void) {
    printf("\n=== Benchmark ===\n");
    printf("%-10s %8s %8s %8s\n", "Grid", "Steps", "Time", "Ground%");
    printf("--------------------------------------\n");

    int sizes[] = {32, 50, 100, 200, 500, 1000};
    for (int si = 0; si < 6; si++) {
        int sz = sizes[si];
        Grid g = grid_create(sz, sz);
        gen_cave(&g, 1.5f, (unsigned)(42 + si*10));
        int sx, sy, gx, gy;
        find_endpoints(&g, &sx, &sy, &gx, &gy);

        int *px, *py, len; float ms;
        len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 200000, &px, &py, &ms);

        int gnd = 0;
        for (int i = 0; i < len; i++)
            if (!grid_walkable(&g, px[i], py[i]+1)) gnd++;

        printf("%4dx%-4d  %6d  %6.1fms  %5.0f%%\n",
               sz, sz, len, ms, len?100.0f*gnd/len:0);

        if (len) { free(px); free(py); }
        grid_free(&g);
    }
}

/* ── Big grid test ───────────────────────────────── */
static void test_big(void) {
    printf("\n=== Big (1000x1000) ===\n");
    Grid g = grid_create(1000, 1000);
    printf("Generating map..."); fflush(stdout);
    gen_cave(&g, 2.0f, 12345u);
    int open = 0;
    for (int i = 0; i < 1000*1000; i++) if (g.cells[i]) open++;
    printf(" %.1f%% open\n", open*100.0/1e6);

    int sx, sy, gx, gy;
    printf("Finding endpoints..."); fflush(stdout);
    find_endpoints(&g, &sx, &sy, &gx, &gy);
    printf(" done\nStart=(%d,%d) Goal=(%d,%d) dist=%d\n",
           sx, sy, gx, gy, abs(gx-sx)+abs(gy-sy));

    int *px, *py, len; float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 200000, &px, &py, &ms);
    printf("Weighted: %d nodes, %.1fms\n", len, ms);
    if (len) { path_stats(&g, px, py, len); free(px); free(py); }
    grid_free(&g);
}

/* ── Huge── ──────────────────────────────────────── */
static void test_huge(void) {
    int sz = 2000;
    printf("\n=== Huge (%dx%d) ===\n", sz, sz);
    Grid g = grid_create(sz, sz);
    printf("Generating map..."); fflush(stdout);
    gen_cave(&g, 2.0f, 99999u);
    long long open = 0;
    for (long long i = 0; i < (long long)sz*sz; i++) if (g.cells[i]) open++;
    printf(" %.1f%% open\n", open*100.0/((long long)sz*sz));

    int sx, sy, gx, gy;
    printf("Finding endpoints..."); fflush(stdout);
    find_endpoints(&g, &sx, &sy, &gx, &gy);
    printf(" done\nStart=(%d,%d) Goal=(%d,%d)\n", sx, sy, gx, gy);

    int *px, *py, len; float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 15, 500000, &px, &py, &ms);
    printf("Weighted: %d nodes, %.1fms\n", len, ms);
    if (len) { path_stats(&g, px, py, len); free(px); free(py); }
    grid_free(&g);
}

/* ── main ────────────────────────────────────────── */
int main(int argc, char **argv) {
    const char *mode = (argc > 1) ? argv[1] : "quick";
    if      (!strcmp(mode, "quick"))  test_quick();
    else if (!strcmp(mode, "bench"))  test_benchmark();
    else if (!strcmp(mode, "big"))    test_big();
    else if (!strcmp(mode, "huge"))   test_huge();
    else if (!strcmp(mode, "all"))    { test_quick(); test_benchmark(); test_big(); test_huge(); }
    else printf("Usage: pathfind_test [quick|bench|big|huge|all]\n");
    return 0;
}
