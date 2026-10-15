#!/usr/bin/env python3
"""Session report for the Archery Target Connect IQ app, from the activity .fit file.

Produces one PNG with:
  1. heat map of the hits on the target (+ group centre)
  2. "aim float" heat map: where the aim was before each release, relative to the
     release point, with the average drift into the release
  3. one small panel per arrow: aim path ending on the hit (approach / aim / break)

usage:  python plot_shots.py activity.fit [--face 80] [--dist 70] [--out report.png]
        --face is detected from the recorded scores when omitted.
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


def trim_release(p, k=3.0, floor_cm=15.0):
    """Drop the release kick: trailing steps much larger than the typical step.
    The path is then re-anchored so its new last point (the aim at release) is 0,0."""
    if p is None or len(p) < 4:
        return p
    steps = np.hypot(*np.diff(p, axis=0).T)
    limit = max(k * np.median(steps[:-1]), floor_cm)
    end = len(p) - 1
    while end > 1 and steps[end - 1] > limit:
        end -= 1
    p = p[:end + 1]
    return p - p[-1]


def read_shots(path):
    from fitparse import FitFile
    fit = FitFile(path)
    n_arrows = None
    for ses in fit.get_messages("session"):
        n_arrows = {f.name: f.value for f in ses.fields}.get("arrows")
    shots = []
    for lap in fit.get_messages("lap"):
        v = {f.name: f.value for f in lap.fields}
        if v.get("shot_x") is None or v.get("shot_y") is None:
            continue
        shots.append(dict(x=v["shot_x"], y=v["shot_y"], score=v.get("shot_score") or 0,
                          hold=v.get("hold_time"), rx=v.get("aim_rms_x") or 0.0,
                          ry=v.get("aim_rms_y") or 0.0, path=smooth(trim_release(decode_path(v.get("aim_path"))))))
    # Saving the activity closes one more lap that still carries the last arrow's values:
    # keep only as many laps as the session's arrow count.
    if n_arrows:
        shots = shots[:n_arrows]
    return shots


def detect_face(shots, faces=(122, 80, 60, 40)):
    """Face diameter whose 10-ring geometry best reproduces the recorded scores."""
    def score(d, face):
        w = face / 20
        return 0 if d > face / 2 else max(1, 10 - int(d / w))
    best = max(faces, key=lambda f: sum(score(math.hypot(s["x"], s["y"]), f) == s["score"]
                                        for s in shots))
    return best


AIM_S = 2.0   # aim phase = last 2 s before the release (same window as the MOA)


def aim_start(p, dt=PATH_DT):
    return max(0, len(p) - 1 - int(round(AIM_S / dt)))


def smooth(p):
    """Light [1 2 1] smoothing for files recorded before the watch averaged its samples;
    re-anchored so the release point stays at 0,0."""
    if p is None or len(p) < 3:
        return p
    q = p.copy()
    q[1:-1] = (p[:-2] + 2 * p[1:-1] + p[2:]) / 4
    return q - q[-1]


def path_wobble(s):
    """Radial RMS (cm at the target) of the aim in the last AIM_S seconds before release,
    from the saved path (kick removed); falls back to the lap fields."""
    p = s["path"]
    if p is not None and len(p) >= 3:
        q = p[aim_start(p):]
        return float(np.sqrt(((q - q.mean(axis=0)) ** 2).sum(axis=1).mean()))
    if s["rx"] or s["ry"]:
        return math.hypot(s["rx"], s["ry"])
    return None


def form_stats(shots, face):
    """Same as ArcheryModel.formStats on the watch: each component is the score an arrow
    would get if that error alone moved it off the centre (10 - error / ring width)."""
    w = face / 20
    xs = np.array([s["x"] for s in shots])
    ys = np.array([s["y"] for s in shots])
    mx, my = xs.mean(), ys.mean()
    sub = lambda rings: float(np.clip(10 - rings, 0, 10))
    acc = sub(math.hypot(mx, my) / w)
    grp = sub(np.mean(np.hypot(xs - mx, ys - my)) / w)
    wob = [v for v in (path_wobble(s) for s in shots) if v is not None]
    stb = sub(np.mean(wob) / w) if wob else None
    parts = [acc, grp] + ([stb] if stb is not None else [])
    return dict(acc=acc, grp=grp, stb=stb, form=float(np.mean(parts)))


def end_size(face):
    return 3 if face <= 40 else 6


def moa(r_cm, dist):
    """Angle (minutes of arc) subtended by r_cm at dist metres."""
    return r_cm / (dist * 100) * 180 / math.pi * 60


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
    n = len(shots)
    xs = np.array([s["x"] for s in shots])
    ys = np.array([s["y"] for s in shots])
    mx, my = xs.mean(), ys.mean()
    # (arrow number, shot) for the arrows that have an aim path
    with_path = [(i, s) for i, s in enumerate(shots, 1) if s["path"] is not None]

    print(f"arrows {n}  total {sum(s['score'] for s in shots)}  avg {np.mean([s['score'] for s in shots]):.2f}")
    print(f"group centre x {mx:+.1f} cm  y {my:+.1f} cm   mean distance {np.mean(np.hypot(xs, ys)):.1f} cm")
    N = end_size(face)
    ends = [form_stats(shots[i:i + N], face) for i in range(0, n - N + 1, N)]
    f_all = form_stats(shots, face)
    stb_txt = f"{f_all['stb']:.1f}" if f_all["stb"] is not None else "--"
    print(f"form  acc {f_all['acc']:.1f}  grp {f_all['grp']:.1f}  stb {stb_txt}  = {f_all['form']:.1f}"
          f"   ({len(ends)} ends of {N})")
    print(" #  score      x      y   hold   aim MOA")
    for i, s in enumerate(shots, 1):
        h = f"{s['hold']:5.1f}" if s["hold"] else "   --"
        wb = path_wobble(s)
        m = f"{moa(wb, dist):6.1f}" if wb is not None else "    --"
        print(f"{i:2d}  {('M' if not s['score'] else s['score']):>5}  {s['x']:+6.1f} {s['y']:+6.1f} {h}  {m}")

    cols = 6
    rows_shots = math.ceil(len(with_path) / cols) if with_path else 0
    fig = plt.figure(figsize=(cols * 2.2, 7.1 + rows_shots * 2.3), facecolor="#111111")
    gs = fig.add_gridspec(2 + rows_shots, cols, height_ratios=[2.3, 1.2] + [1] * rows_shots)

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
        for _, s in with_path:
            p = s["path"][aim_start(s["path"]):]
            if len(p) < 2:
                continue
            fx += list(p[:, 0])
            fy += list(p[:, 1])
            bias.append(-p.mean(axis=0))
        rr = np.median([path_wobble(s) for _, s in with_path])
        span = float(np.clip(2.5 * rr, 3, R))
        b = np.mean(bias, axis=0) if bias else np.zeros(2)
        names = ["right", "up-right", "up", "up-left", "left", "down-left", "down", "down-right"]
        ang = math.degrees(math.atan2(b[1], b[0])) % 360
        way = names[int((ang + 22.5) // 45) % 8] if math.hypot(*b) >= 0.3 else "none"
        style(ax, f"Aim float before release  (drift {math.hypot(*b):.1f} cm {way})")
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

    # 3. form by end (warm-up / fatigue)
    ax = fig.add_subplot(gs[1, :])
    ax.set_facecolor("#111111")
    for sp in ax.spines.values():
        sp.set_color("#333333")
    ax.tick_params(colors="#aaaaaa", labelsize=8)
    if len(ends) >= 2:
        e = np.arange(1, len(ends) + 1)
        for key, col, lw in (("acc", AIM, 1.2), ("grp", "#3ad86b", 1.2), ("stb", APPR, 1.2), ("form", "white", 2.6)):
            v = [d[key] if d[key] is not None else np.nan for d in ends]
            ax.plot(e, v, color=col, lw=lw, marker="o", ms=3, label=key.upper())
        ax.set_xticks(e)
        ax.set_xlabel(f"end ({N} arrows)", color="#aaaaaa", fontsize=8)
        ax.legend(loc="lower right", fontsize=8, facecolor="#111111", labelcolor="white", edgecolor="#333333", ncol=4)
        peak = int(np.argmax([d["form"] for d in ends])) + 1
        ax.axvline(peak, color="#555555", lw=0.8, ls="--")
        ax.set_title(f"Form by end  (session {f_all['form']:.1f}; peak at end {peak})", color="white", fontsize=10)
    else:
        ax.set_title(f"Form by end: needs at least {2 * N} arrows", color="white", fontsize=10)

    # 4. one panel per arrow
    for k, (num, s) in enumerate(with_path):
        ax = fig.add_subplot(gs[2 + k // cols, k % cols])
        p = s["path"] + [s["x"], s["y"]]
        a = aim_start(s["path"])
        style(ax, f"#{num}  {s['score'] or 'M'}  ·  {moa(path_wobble(s), dist):.1f} MOA")
        rings(ax, R)
        ax.plot(p[:a + 1, 0], p[:a + 1, 1], color=APPR, lw=1.2, zorder=4)
        ax.plot(p[a:, 0], p[a:, 1], color=AIM, lw=1.4, zorder=5)
        ax.scatter([s["x"]], [s["y"]], s=22, c=BREAK, edgecolors="white", linewidths=0.6, zorder=6)
        # zoom: enough to show the aim phase in full, between 30 % and 110 % of the face radius
        z = float(np.clip(1.3 * np.abs(s["path"][a:]).max(), R * 0.3, R * 1.1))
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
    ap.add_argument("--face", type=float, default=None,
                    help="face diameter in cm (default: detected from the scores)")
    ap.add_argument("--dist", type=float, default=70.0, help="shooting distance in m (for MOA)")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    shots = read_shots(a.fit)
    if not shots:
        raise SystemExit("no arrows found (lap fields shot_x/shot_y missing)")
    face = a.face or detect_face(shots)
    if a.face is None:
        print(f"target face: {face} cm (detected from the scores; use --face to override)")
    report(shots, face, a.dist, a.out)


if __name__ == "__main__":
    main()
