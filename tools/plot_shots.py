#!/usr/bin/env python3
"""Session report for the Archery Target Connect IQ app, from the activity .fit file.

Produces one PNG with:
  1. heat map of the hits on the target (+ group centre)
  2. "aim float" heat map: where the aim was before each release, relative to the
     release point, with the average drift into the release
  3. one small panel per arrow: aim path ending on the hit (approach / aim / break)

usage:  python plot_shots.py activity.fit [--face 122] [--dist 70] [--out report.png]
needs:  pip install fitparse matplotlib numpy
"""
import argparse
import math

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Circle

PATH_DT = 0.2        # must match FIT_PATH_DT in ArcheryModel.mc
PATH_SCALE = 4.0     # must match FIT_PATH_SCALE
RING = {1: "white", 2: "white", 3: "black", 4: "black", 5: "#1e90ff",
        6: "#1e90ff", 7: "red", 8: "red", 9: "gold", 10: "gold"}
APPR, AIM, BREAK = "#b03ad8", "#3aa0ff", "#ff2a2a"


def decode_path(raw):
    """Interleaved x,y in 1/4 cm, oldest first; 32767 / None = missing."""
    if raw is None:
        return None
    if not isinstance(raw, (list, tuple)):
        raw = [raw]
    pts = []
    for i in range(0, len(raw) - 1, 2):
        x, y = raw[i], raw[i + 1]
        if x is None or y is None or x == 32767 or y == 32767:
            continue
        pts.append((x / PATH_SCALE, y / PATH_SCALE))
    return np.array(pts) if len(pts) > 1 else None


def read_shots(path):
    from fitparse import FitFile
    shots = []
    for lap in FitFile(path).get_messages("lap"):
        v = {f.name: f.value for f in lap.fields}
        if v.get("shot_x") is None or v.get("shot_y") is None:
            continue
        shots.append(dict(x=v["shot_x"], y=v["shot_y"], score=v.get("shot_score") or 0,
                          hold=v.get("hold_time"), rx=v.get("aim_rms_x") or 0.0,
                          ry=v.get("aim_rms_y") or 0.0, path=decode_path(v.get("aim_path"))))
    return shots


def aim_start(p, split):
    """First index of the final segment that stays within `split` cm of the break."""
    far = np.nonzero(np.hypot(p[:, 0], p[:, 1]) > split)[0]
    return int(far[-1]) + 1 if len(far) else 0


def moa(rx, ry, dist):
    return math.hypot(rx, ry) / (dist * 100) * 180 / math.pi * 60


def heat(ax, xs, ys, span, bins=40, sigma=1.5):
    h, _, _ = np.histogram2d(ys, xs, bins=bins, range=[[-span, span], [-span, span]])
    k = np.exp(-0.5 * (np.arange(-4, 5) / sigma) ** 2)
    k /= k.sum()
    h = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 0, h)
    h = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 1, h)
    h = np.ma.masked_less(h / (h.max() or 1), 0.08)
    ax.imshow(h, extent=[-span, span, -span, span], origin="lower", cmap="turbo",
              alpha=0.85, zorder=2)


def rings(ax, R, filled=False):
    for s in range(1, 11):
        r = R * (11 - s) / 10
        if filled:
            ax.add_patch(Circle((0, 0), r, facecolor=RING[s],
                                edgecolor="white" if s in (3, 4) else "black", lw=0.6, zorder=1))
        else:
            ax.add_patch(Circle((0, 0), r, fill=False, lw=0.6, zorder=3,
                                edgecolor="#bbbbbb" if s % 2 else "#666666"))


def report(shots, face, dist, out=None):
    R = face / 2
    split = face * 0.15
    n = len(shots)
    xs = np.array([s["x"] for s in shots])
    ys = np.array([s["y"] for s in shots])
    mx, my = xs.mean(), ys.mean()
    with_path = [s for s in shots if s["path"] is not None]

    print(f"arrows {n}  total {sum(s['score'] for s in shots)}  avg {np.mean([s['score'] for s in shots]):.2f}")
    print(f"group centre x {mx:+.1f} cm  y {my:+.1f} cm   mean distance {np.mean(np.hypot(xs, ys)):.1f} cm")
    print(" #  score      x      y   hold   aim MOA")
    for i, s in enumerate(shots, 1):
        h = f"{s['hold']:5.1f}" if s["hold"] else "   --"
        m = f"{moa(s['rx'], s['ry'], dist):6.1f}" if s["path"] is not None else "    --"
        print(f"{i:2d}  {('M' if not s['score'] else s['score']):>5}  {s['x']:+6.1f} {s['y']:+6.1f} {h}  {m}")

    cols = 6
    rows_shots = math.ceil(len(with_path) / cols) if with_path else 0
    fig = plt.figure(figsize=(cols * 2.2, 5.2 + rows_shots * 2.3), facecolor="#111111")
    gs = fig.add_gridspec(1 + rows_shots, cols, height_ratios=[2.3] + [1] * rows_shots)

    def style(ax, title):
        ax.set_facecolor("#111111")
        ax.set_aspect("equal")
        ax.set_xticks([])
        ax.set_yticks([])
        for sp in ax.spines.values():
            sp.set_color("#333333")
        ax.set_title(title, color="white", fontsize=10)

    # 1. hits
    ax = fig.add_subplot(gs[0, 0:3])
    style(ax, f"Hits  ({n} arrows, group {mx:+.1f}, {my:+.1f} cm)")
    heat(ax, xs, ys, R * 1.1)
    rings(ax, R)
    ax.scatter(xs, ys, s=10, c="white", zorder=4)
    ax.scatter([mx], [my], s=140, marker="+", c="#ff4fd8", linewidths=2.5, zorder=5)
    ax.set_xlim(-R * 1.1, R * 1.1)
    ax.set_ylim(-R * 1.1, R * 1.1)

    # 2. aim float relative to the release
    ax = fig.add_subplot(gs[0, 3:6])
    if with_path:
        fx, fy, bias = [], [], []
        for s in with_path:
            p = s["path"][aim_start(s["path"], split):]
            if len(p) < 2:
                continue
            fx += list(p[:, 0])
            fy += list(p[:, 1])
            bias.append(-p.mean(axis=0))
        rr = np.mean([math.hypot(s["rx"], s["ry"]) for s in with_path])
        span = float(np.clip(2.5 * rr, 3, R))
        b = np.mean(bias, axis=0) if bias else np.zeros(2)
        style(ax, f"Aim float before release  (drift {math.hypot(*b):.1f} cm)")
        heat(ax, np.array(fx), np.array(fy), span)
        ax.axhline(0, color="#555555", lw=0.6)
        ax.axvline(0, color="#555555", lw=0.6)
        ax.annotate("", xy=(0, 0), xytext=(-b[0], -b[1]), zorder=5,
                    arrowprops=dict(arrowstyle="-|>", color="white", lw=2))
        ax.scatter([0], [0], s=40, c=BREAK, zorder=6)
        ax.set_xlim(-span, span)
        ax.set_ylim(-span, span)
        ax.set_xlabel("cm (release point at centre)", color="#aaaaaa", fontsize=8)
    else:
        style(ax, "Aim float: no aim data")

    # 3. one panel per arrow
    for k, s in enumerate(with_path):
        ax = fig.add_subplot(gs[1 + k // cols, k % cols])
        p = s["path"] + [s["x"], s["y"]]
        a = aim_start(s["path"], split)
        style(ax, f"#{shots.index(s) + 1}  {s['score'] or 'M'}  ·  {moa(s['rx'], s['ry'], dist):.1f} MOA")
        rings(ax, R)
        ax.plot(p[:a + 1, 0], p[:a + 1, 1], color=APPR, lw=1.2, zorder=4)
        ax.plot(p[a:, 0], p[a:, 1], color=AIM, lw=1.4, zorder=5)
        ax.scatter([s["x"]], [s["y"]], s=22, c=BREAK, edgecolors="white", linewidths=0.6, zorder=6)
        z = max(split * 1.6, R * 0.45)
        ax.set_xlim(s["x"] - z, s["x"] + z)
        ax.set_ylim(s["y"] - z, s["y"] + z)
        ax.text(0.03, 0.03, f"appr {a * PATH_DT:.1f}s  aim {(len(p) - 1 - a) * PATH_DT:.1f}s",
                transform=ax.transAxes, color="#cccccc", fontsize=7)

    fig.tight_layout()
    if out:
        fig.savefig(out, dpi=130, facecolor=fig.get_facecolor())
        print("saved", out)
    else:
        plt.show()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("fit")
    ap.add_argument("--face", type=float, default=122.0, help="face diameter in cm")
    ap.add_argument("--dist", type=float, default=70.0, help="shooting distance in m (for MOA)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    shots = read_shots(a.fit)
    if not shots:
        raise SystemExit("no arrows found (lap fields shot_x/shot_y missing)")
    report(shots, a.face, a.dist, a.out)


if __name__ == "__main__":
    main()
