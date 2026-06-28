/*
 * bridge.c — file-IPC bridge: reads input.bin, writes output.bin
 *
 * Input format (input.bin):
 *   int32  width, height
 *   int32  start_x, start_y, goal_x, goal_y
 *   uint8  cells[height][width]  row-major, 1=walkable 0=wall
 *
 * Output format (output.bin):
 *   int32  path_length  (0 = no path)
 *   float  elapsed_ms
 *   int32  px[path_length], py[path_length]
 */
#include "pathfind.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    const char *infile  = (argc > 1) ? argv[1] : "pf_in.bin";
    const char *outfile = (argc > 2) ? argv[2] : "pf_out.bin";

    FILE *f = fopen(infile, "rb");
    if (!f) { fprintf(stderr, "Cannot open %s\n", infile); return 1; }

    int w, h, sx, sy, gx, gy;
    if (fread(&w, 4, 1, f) != 1) goto fail;
    if (fread(&h, 4, 1, f) != 1) goto fail;
    if (fread(&sx, 4, 1, f) != 1) goto fail;
    if (fread(&sy, 4, 1, f) != 1) goto fail;
    if (fread(&gx, 4, 1, f) != 1) goto fail;
    if (fread(&gy, 4, 1, f) != 1) goto fail;

    Grid g = grid_create(w, h);
    if (fread(g.cells, 1, (size_t)w * h, f) != (size_t)w * h) {
        grid_free(&g); fclose(f); fprintf(stderr, "Short read\n"); return 1;
    }
    fclose(f);

    /* Run pathfinding */
    int *px, *py, len;
    float ms;
    len = pathfind_weighted(&g, sx, sy, gx, gy, 31, 2000000, &px, &py, &ms);

    /* Write output */
    f = fopen(outfile, "wb");
    if (!f) { grid_free(&g); return 1; }
    fwrite(&len, 4, 1, f);
    fwrite(&ms,  4, 1, f);
    if (len > 0) {
        fwrite(px, 4, (size_t)len, f);
        fwrite(py, 4, (size_t)len, f);
        free(px); free(py);
    }
    fclose(f);
    grid_free(&g);
    return 0;

fail:
    fclose(f);
    fprintf(stderr, "Bad input format\n");
    return 1;
}
