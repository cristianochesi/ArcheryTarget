import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Shared drawing / formatting helpers.
module ArcheryUi {

    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    const HR_HISTORY = 120;   // bars in the HR zone graph (one every 2 s = 4 min)

    // Size factor relative to the 260 px Forerunner 955 screen (1.0 there, ~1.75 on 454 px AMOLED).
    function scale(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        return ((w < h) ? w : h) / 260.0;
    }

    // WA colours: 1-2 white, 3-4 black, 5-6 blue, 7-8 red, 9-10 gold
    function ringColor(score) {
        if (score <= 2) { return Graphics.COLOR_WHITE; }
        if (score <= 4) { return Graphics.COLOR_BLACK; }
        if (score <= 6) { return Graphics.COLOR_BLUE; }
        if (score <= 8) { return Graphics.COLOR_RED; }
        return Graphics.COLOR_YELLOW;
    }

    // Draws a 10-ring target face of radius r centred on (cx, cy).
    function drawFace(dc, cx, cy, r) as Void {
        dc.setPenWidth(1);
        for (var s = 1; s <= 10; s += 1) {
            var rr = r * (11 - s) / 10.0;
            var c = ringColor(s);
            dc.setColor(c, c);
            dc.fillCircle(cx, cy, rr);
            var line = (s == 3 || s == 4) ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
            dc.setColor(line, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, rr);
        }
        // inner "X" ring and centre dot
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r / 20.0);
        dc.fillCircle(cx, cy, 1);
    }

    // Score of a point at (dx, dy) from the centre of a target of radius r
    // (all in the same unit). Outside the face = 0 (miss).
    function scoreFor(dx, dy, r) {
        var d = Math.sqrt(dx * dx + dy * dy);
        if (d > r) {
            return 0;
        }
        var s = 10 - (d * 10.0 / r).toNumber();
        return (s < 1) ? 1 : s;
    }

    function scoreLabel(score) {
        return (score == 0) ? "M" : score.toString();
    }

    function signed(v) {
        return ((v >= 0) ? "+" : "") + v.format("%.1f");
    }

    function formatTime(ms) {
        var t = (ms == null) ? 0 : ms / 1000;
        var h = t / 3600;
        var m = (t % 3600) / 60;
        var s = t % 60;
        if (h > 0) {
            return h.toString() + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.format("%02d") + ":" + s.format("%02d");
    }

    // ------------------------------------------------------------ report helpers

    // Dark target (ring lines only), used under heat maps and aim paths.
    // fill = false draws the lines only (on top of a heat map).
    function drawRings(dc, cx, cy, r, fill) as Void {
        dc.setPenWidth(1);
        if (fill) {
            dc.setColor(Graphics.COLOR_DK_BLUE, Graphics.COLOR_DK_BLUE);
            dc.fillCircle(cx, cy, r * 0.2);                   // 9-10 zone
        }
        for (var s = 1; s <= 10; s += 1) {
            dc.setColor((s % 2 == 1) ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY,
                Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r * (11 - s) / 10.0);
        }
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(cx - r, cy, cx + r, cy);
        dc.drawLine(cx, cy - r, cx, cy + r);
    }

    // 0..1 -> heat colour, or null below the visibility threshold.
    function heatColor(v) {
        if (v < 0.12) { return null; }
        if (v < 0.30) { return Graphics.COLOR_DK_BLUE; }
        if (v < 0.48) { return Graphics.COLOR_BLUE; }
        if (v < 0.64) { return Graphics.COLOR_GREEN; }
        if (v < 0.80) { return Graphics.COLOR_YELLOW; }
        if (v < 0.92) { return Graphics.COLOR_ORANGE; }
        return Graphics.COLOR_RED;
    }

    // Square grid n x n covering [-span, span] cm on both axes (row 0 = top).
    // Adds 1 to the cell of each point; points outside are ignored.
    function gridAdd(g as Array<Float>, n as Number, span, x, y) as Void {
        var c = ((x + span) * n / (2.0 * span)).toNumber();
        var r = ((span - y) * n / (2.0 * span)).toNumber();
        if (c >= 0 && c < n && r >= 0 && r < n) {
            g[r * n + c] = g[r * n + c] + 1.0;
        }
    }

    // Two passes of a separable [1 2 1] blur, then normalised to max = 1.
    function gridSmooth(g as Array<Float>, n as Number) as Array<Float> {
        var a = g;
        for (var pass = 0; pass < 2; pass += 1) {
            var b = new [n * n] as Array<Float>;
            for (var r = 0; r < n; r += 1) {
                for (var c = 0; c < n; c += 1) {
                    var v = 2.0 * a[r * n + c];
                    if (c > 0) { v += a[r * n + c - 1]; }
                    if (c < n - 1) { v += a[r * n + c + 1]; }
                    b[r * n + c] = v;
                }
            }
            a = new [n * n] as Array<Float>;
            for (var r = 0; r < n; r += 1) {
                for (var c = 0; c < n; c += 1) {
                    var v = 2.0 * b[r * n + c];
                    if (r > 0) { v += b[(r - 1) * n + c]; }
                    if (r < n - 1) { v += b[(r + 1) * n + c]; }
                    a[r * n + c] = v;
                }
            }
        }
        var mx = 0.0;
        for (var i = 0; i < n * n; i += 1) {
            if (a[i] > mx) { mx = a[i]; }
        }
        if (mx > 0) {
            for (var i = 0; i < n * n; i += 1) {
                a[i] = a[i] / mx;
            }
        }
        return a;
    }

    // Draws the grid centred on (cx, cy); size = full side in px.
    function drawGrid(dc, g as Array<Float>, n as Number, cx, cy, size) as Void {
        var cell = size / n;
        var x0 = cx - size / 2.0;
        var y0 = cy - size / 2.0;
        for (var r = 0; r < n; r += 1) {
            for (var c = 0; c < n; c += 1) {
                var col = heatColor(g[r * n + c]);
                if (col != null) {
                    dc.setColor(col, col);
                    dc.fillRectangle(x0 + c * cell, y0 + r * cell, cell + 1, cell + 1);
                }
            }
        }
    }

    // Index where the "aim" phase begins: after the last sample farther than splitCm
    // from the break (the path ends at the break, at 0,0). Before it = "approach".
    function aimStart(px as Array<Float>, py as Array<Float>, splitCm) as Number {
        var s2 = splitCm * splitCm;
        for (var i = px.size() - 1; i >= 0; i -= 1) {
            var x = px[i];
            var y = py[i];
            if (x * x + y * y > s2) {
                return i + 1;
            }
        }
        return 0;
    }

    // Polyline of path points [from, to) drawn at (ox + x*k, oy - y*k).
    function drawPath(dc, px as Array<Float>, py as Array<Float>, from as Number, to as Number,
                      ox, oy, k, color, pen) as Void {
        if (to - from < 2) { return; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        var lx = ox + px[from] * k;
        var ly = oy - py[from] * k;
        for (var i = from + 1; i < to; i += 1) {
            var x = ox + px[i] * k;
            var y = oy - py[i] * k;
            dc.drawLine(lx, ly, x, y);
            lx = x;
            ly = y;
        }
        dc.setPenWidth(1);
    }

    // Aim steadiness as an angle: radial RMS in cm at distM metres -> minutes of angle.
    function moa(rmsX, rmsY, distM) {
        var r = Math.sqrt(rmsX * rmsX + rmsY * rmsY);
        return (r / (distM * 100.0) * 180.0 / Math.PI * 60.0).toFloat();
    }
}
