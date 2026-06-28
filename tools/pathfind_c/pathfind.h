/*
 * pathfind.h — Weighted A* with exponential flight fatigue (C implementation)
 *
 * Usage:
 *   Grid g = grid_create(w, h);
 *   // fill g.cells with walkable data (1=walkable, 0=wall)
 *   int *px, *py, len;
 *   float ms;
 *   len = pathfind_weighted(&g, sx, sy, gx, gy, &px, &py, &ms);
 *   // px[0..len-1], py[0..len-1] is the path
 *   free(px); free(py);
 *   grid_free(&g);
 */
#ifndef PATHFIND_H
#define PATHFIND_H

#include <stdint.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Grid ────────────────────────────────────────── */
typedef struct {
    int      w, h;       /* width, height */
    uint8_t *cells;      /* row-major: cells[y*w + x], 1=walkable */
} Grid;

Grid  grid_create(int w, int h);
void  grid_free(Grid *g);
int   grid_walkable(const Grid *g, int x, int y);

/* ── Pathfinding result ──────────────────────────── */
/*
 * Returns path length (number of nodes), 0 = no path / error.
 * On success, (*px, *py) is malloc'd; caller must free both.
 * *elapsed_ms receives wall-clock time in milliseconds.
 */
int pathfind_weighted(
    const Grid *g,
    int sx, int sy,
    int gx, int gy,
    int max_air,
    int max_iter,
    int **px,
    int **py,
    float *elapsed_ms
);

#ifdef __cplusplus
}
#endif
#endif /* PATHFIND_H */
