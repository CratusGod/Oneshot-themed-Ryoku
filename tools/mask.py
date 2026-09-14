#!/usr/bin/env python3
"""Emit a 1-bit PGM mask of a two-line 5x5 pixel wordmark.

Glyph shapes for R, O, U, K, Y are lifted verbatim from the shipped Ryoku
wordmark so the new letters sit on the same grid and carry the same weight.
"""
import sys

CELL_ROWS = 5
GLYPHS = {
    " ": (".....", ".....", ".....", ".....", "....."),
    "A": (".###.", "#...#", "#####", "#...#", "#...#"),
    "C": ("#####", "#....", "#....", "#....", "#####"),
    "D": ("####.", "#...#", "#...#", "#...#", "####."),
    "E": ("#####", "#....", "####.", "#....", "#####"),
    "H": ("#...#", "#...#", "#####", "#...#", "#...#"),
    "I": ("#####", "..#..", "..#..", "..#..", "#####"),
    "L": ("#....", "#....", "#....", "#....", "#####"),
    "M": ("#...#", "##.##", "#.#.#", "#...#", "#...#"),
    "N": ("#...#", "##..#", "#.#.#", "#..##", "#...#"),
    "O": ("#####", "#...#", "#...#", "#...#", "#####"),
    "R": ("####.", "#..#.", "####.", "#.#..", "#..#."),
    "T": ("#####", "..#..", "..#..", "..#..", "..#.."),
    "W": ("#...#", "#...#", "#.#.#", "##.##", "#...#"),
}


def lay_out(word):
    """Render one word into a list of row strings, one cell per character."""
    rows = [""] * CELL_ROWS
    for index, char in enumerate(word):
        glyph = GLYPHS[char]
        for row in range(CELL_ROWS):
            if index:
                rows[row] += "."
            rows[row] += glyph[row]
    return rows


def main():
    top, bottom, gap = sys.argv[1], sys.argv[2], int(sys.argv[3])
    align = sys.argv[4] if len(sys.argv) > 4 else "center"
    upper, lower = lay_out(top), lay_out(bottom)
    width = max(len(upper[0]), len(lower[0]))

    def centred(rows):
        slack = width - len(rows[0])
        pad = {"left": 0, "right": slack}.get(align, slack // 2)
        return ["." * pad + r + "." * (width - len(r) - pad) for r in rows]

    grid = centred(upper) + ["." * width] * gap + centred(lower)
    out = ["P2", f"{width} {len(grid)}", "255"]
    for row in grid:
        out.append(" ".join("255" if c == "#" else "0" for c in row))
    sys.stdout.write("\n".join(out) + "\n")


main()
