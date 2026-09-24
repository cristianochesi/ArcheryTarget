#!/usr/bin/env python3
"""Plot the arrows recorded by the Archery Target Connect IQ app from a .fit file.

usage:  python plot_shots.py activity.fit [--face 122] [--out shots.png]
needs:  pip install fitparse matplotlib
"""
import argparse
import math

import matplotlib.pyplot as plt
from fitparse import FitFile
from matplotlib.patches import Circle

RING = {1: "white", 2: "white", 3: "black", 4: "black", 5: "#1e90ff",
        6: "#1e90ff", 7: "red", 8: "red", 9: "gold", 10: "gold"}


def read_shots(path):
    shots = []
    for lap in FitFile(path).get_messages("lap"):
        v = {f.name: f.value for f in lap.fields}
        if v.get("shot_x") is not None and v.get("shot_y") is not None:
            shots.append((v["shot_x"], v["shot_y"], v.get("shot_score"),
                          v.get("hold_time"), v.get("aim_rms_x"), v.get("aim_rms_y")))
    return shots


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fit")
    ap.add_argument("--face", type=float, default=122.0, help="face diameter in cm")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()

    shots = read_shots(a.fit)
    if not shots:
        raise SystemExit("no arrows found (lap fields shot_x/shot_y missing)")
    xs, ys, sc = [s[0] for s in shots], [s[1] for s in shots], [s[2] for s in shots]
    print(" #  score      x      y   hold  rmsX  rmsY")
    for i, (x, y, s, h, rx, ry) in enumerate(shots, 1):
        f = lambda v, p=1: "  --" if v in (None, 0) else f"{v:6.{p}f}"
        print(f"{i:2d}  {('M' if not s else s):>5}  {x:+6.1f} {y:+6.1f} {f(h)} {f(rx)} {f(ry)}")
    n = len(shots)
    mx, my = sum(xs) / n, sum(ys) / n
    md = sum(math.hypot(x, y) for x, y in zip(xs, ys)) / n
    print(f"arrows {n}  total {sum(s or 0 for s in sc)}")
    print(f"group centre  x {mx:+.1f} cm  y {my:+.1f} cm")
    print(f"mean |x| {sum(map(abs, xs)) / n:.1f} cm  mean |y| {sum(map(abs, ys)) / n:.1f} cm  "
          f"mean distance {md:.1f} cm")

    R = a.face / 2
    fig, ax = plt.subplots(figsize=(6, 6))
    for s in range(1, 11):
        ax.add_patch(Circle((0, 0), R * (11 - s) / 10, facecolor=RING[s],
                            edgecolor="white" if s in (3, 4) else "black", lw=0.8))
    ax.scatter(xs, ys, s=30, c="magenta", edgecolors="black", zorder=3, label="arrows")
    ax.scatter([mx], [my], s=120, marker="+", c="green", linewidths=3, zorder=4,
               label=f"group centre ({mx:+.1f}, {my:+.1f}) cm")
    lim = R * 1.1
    ax.set_xlim(-lim, lim)
    ax.set_ylim(-lim, lim)
    ax.set_aspect("equal")
    ax.set_xlabel("x (cm)")
    ax.set_ylabel("y (cm)")
    ax.legend(loc="upper right", fontsize=8)
    if a.out:
        fig.savefig(a.out, dpi=150, bbox_inches="tight")
    else:
        plt.show()


if __name__ == "__main__":
    main()
