import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// End-of-session report. UP / DOWN (or swipe) change page:
//   0  summary numbers
//   1  form by end: accuracy, grouping, stability and form for each end (warm-up / fatigue)
//   2  heat map of the hits on the target
//   3  heat map of where the aim floated before each release, relative to the release
//      point, with the average drift into the release (the "bending" tendency)
//   4+ one page per arrow: aim path ending on the hit (approach purple, aim blue, break red).
//      Tap = zoom x3 around the hit.
class ReportView extends WatchUi.View {

    const GRID = 20;

    var page = 0;
    var zoom = false;
    private var _m;
    private var _hits = null;      // smoothed grids, built the first time they are shown
    private var _float = null;
    private var _floatSpan = 10.0;
    private var _biasX = 0.0;      // average aim movement into the release (cm)
    private var _biasY = 0.0;
    private var _floatN = 0;

    function initialize(model) {
        View.initialize();
        _m = model;
    }

    function pageCount() {
        return 4 + _m.count();
    }

    function move(d) as Void {
        var n = pageCount();
        page = (page + d + n) % n;
        zoom = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 0) {
            drawStats(dc);
        } else if (page == 1) {
            drawEnds(dc);
        } else if (page == 2) {
            drawHits(dc);
        } else if (page == 3) {
            drawFloat(dc);
        } else {
            drawShot(dc, page - 4);
        }
        // page dots / counter
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.955, Graphics.FONT_XTINY,
            (page + 1).toString() + "/" + pageCount().toString(), ArcheryUi.CENTER);
    }

    private function title(dc, txt) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.09, Graphics.FONT_XTINY, txt, ArcheryUi.CENTER);
    }

    // ------------------------------------------------------------ page 0

    private function drawStats(dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var C = ArcheryUi.CENTER;
        var n = _m.count();
        title(dc, "SESSION REPORT");

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.22, Graphics.FONT_MEDIUM,
            _m.total.toString() + " pts", C);

        var lines = [
            n.toString() + " arrows  avg " + ((n > 0) ? _m.avgScore().format("%.1f") : "--"),
            "time " + ArcheryUi.formatTime(_m.durationMs()),
            "group X " + ArcheryUi.signed(_m.meanX()) + "  Y " + ArcheryUi.signed(_m.meanY()) + " cm",
            "hold " + _m.avgHold().format("%.1f") + " s  aim "
                + ArcheryUi.moa(_m.avgRmsX(), _m.avgRmsY(), _m.distM).format("%.1f") + " MOA",
            formLine(),
            "HR avg " + hrTxt(_m.hrAvg) + "  max " + hrTxt(_m.hrMax),
            "resp " + ((_m.respAvg > 0) ? _m.respAvg.format("%.0f") : "--") + " brpm"
        ];
        var y0 = h * 0.35;
        var lh = dc.getFontHeight(Graphics.FONT_XTINY) * 1.05;
        for (var i = 0; i < lines.size(); i += 1) {
            dc.setColor((i == 0) ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, y0 + i * lh, Graphics.FONT_XTINY, lines[i], C);
        }
    }

    // Whole-session form: A(ccuracy) G(rouping) S(tability) = F(orm)
    private function formLine() {
        var n = _m.count();
        if (n < 3) { return "form --"; }
        var f = _m.formStats(0, n);
        return "A " + f[0].format("%.1f") + " G " + f[1].format("%.1f")
            + " S " + ((f[2] >= 0) ? f[2].format("%.1f") : "--") + " = " + f[3].format("%.1f");
    }

    private function hrTxt(v) {
        return (v > 0) ? v.toString() : "--";
    }

    // ------------------------------------------------------------ page 1

    private function drawEnds(dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var sk = ArcheryUi.scale(dc);
        title(dc, "FORM BY END");
        var ends = _m.ends as Array<Array<Float>>;
        var n = ends.size();
        if (n < 2) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY,
                "needs 2 ends (" + (2 * _m.endSize()).toString() + " arrows)", ArcheryUi.CENTER);
            return;
        }
        // plot area: score scale, auto-ranged on the data (at least 3 points tall)
        var x0 = w * 0.17;
        var x1 = w * 0.85;
        var y0 = h * 0.22;
        var y1 = h * 0.72;
        var lo = 10.0;
        var hi = 0.0;
        for (var i = 0; i < n; i += 1) {
            for (var k = 0; k < 4; k += 1) {
                var v = ends[i][k];
                if (v < 0) { continue; }
                if (v < lo) { lo = v; }
                if (v > hi) { hi = v; }
            }
        }
        lo = Math.floor(lo).toFloat();
        hi = Math.ceil(hi).toFloat();
        if (hi - lo < 3) { lo = hi - 3; }
        if (lo < 0) { lo = 0.0; hi = (hi < 3) ? 3.0 : hi; }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x0, y0, x1 - x0, y1 - y0);
        dc.drawText(x0 - 3, y0, Graphics.FONT_XTINY, hi.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x0 - 3, y1, Graphics.FONT_XTINY, lo.format("%d"), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);

        var cols = [Graphics.COLOR_BLUE, Graphics.COLOR_GREEN, Graphics.COLOR_PURPLE, Graphics.COLOR_WHITE];
        for (var k = 0; k < 4; k += 1) {
            dc.setPenWidth((((k == 3) ? 3 : 1) * sk + 0.5).toNumber());
            dc.setColor(cols[k], Graphics.COLOR_TRANSPARENT);
            var px = null;
            var py = null;
            for (var i = 0; i < n; i += 1) {
                var v = ends[i][k];
                if (v < 0) { px = null; continue; }
                var x = x0 + (x1 - x0) * i / (n - 1.0);
                var y = y1 - (y1 - y0) * (v - lo) / (hi - lo);
                if (px != null) { dc.drawLine(px, py, x, y); }
                px = x;
                py = y;
            }
        }
        dc.setPenWidth(1);

        // legend + end axis
        var C = ArcheryUi.CENTER;
        var lab = ["ACC", "GRP", "STB", "FORM"];
        for (var k = 0; k < 4; k += 1) {
            dc.setColor(cols[k], Graphics.COLOR_TRANSPARENT);
            dc.drawText(w * (0.23 + 0.18 * k), h * 0.80, Graphics.FONT_XTINY, lab[k], C);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.755, Graphics.FONT_XTINY,
            "end 1 .. " + n.toString() + "  (" + _m.endSize().toString() + " arrows)", C);
        dc.drawText(w / 2, h * 0.87, Graphics.FONT_XTINY,
            (_m.phase.length() > 0) ? "now: " + _m.phase : "", C);
    }

    // ------------------------------------------------------------ page 2

    private function drawHits(dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2.0;
        var cy = h * 0.52;
        var r = h * 0.34;
        var R = _m.faceCm / 2.0;
        var span = R * 1.1;
        title(dc, "HITS");

        var shots = _m.shots as Array<Array>;
        if (_hits == null) {
            var g = zeros();
            for (var i = 0; i < shots.size(); i += 1) {
                var s = shots[i];
                ArcheryUi.gridAdd(g, GRID, span, s[0], s[1]);
            }
            _hits = ArcheryUi.gridSmooth(g, GRID);
        }
        ArcheryUi.drawGrid(dc, _hits, GRID, cx, cy, 2 * r * 1.1);
        ArcheryUi.drawRings(dc, cx, cy, r, false);

        var k = r / R;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < shots.size(); i += 1) {
            var s = shots[i];
            dc.fillCircle(cx + s[0] * k, cy - s[1] * k, 1.5 * ArcheryUi.scale(dc));
        }
        if (shots.size() > 0) {
            var gx = cx + _m.meanX() * k;
            var gy = cy - _m.meanY() * k;
            var c = 6 * ArcheryUi.scale(dc);
            dc.setPenWidth((2 * ArcheryUi.scale(dc) + 0.5).toNumber());
            dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(gx - c, gy, gx + c, gy);
            dc.drawLine(gx, gy - c, gx, gy + c);
            dc.setPenWidth(1);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.89, Graphics.FONT_XTINY,
            "+ group X " + ArcheryUi.signed(_m.meanX()) + " Y " + ArcheryUi.signed(_m.meanY()), ArcheryUi.CENTER);
    }

    // ------------------------------------------------------------ page 3

    private function buildFloat() as Void {
        var shots = _m.shots as Array<Array>;
        // scale: 2.5 x the average radial steadiness, between 3 cm and the face radius
        var rr = 0.0;
        var nr = 0;
        for (var i = 0; i < shots.size(); i += 1) {
            var s = shots[i];
            if (s[4] == null) { continue; }
            rr += Math.sqrt(s[7] * s[7] + s[8] * s[8]);
            nr += 1;
        }
        _floatSpan = (nr > 0) ? 2.5 * rr / nr : 10.0;
        if (_floatSpan < 3.0) { _floatSpan = 3.0; }
        if (_floatSpan > _m.faceCm / 2.0) { _floatSpan = _m.faceCm / 2.0; }

        var g = zeros();
        var bx = 0.0;
        var by = 0.0;
        _floatN = 0;
        for (var i = 0; i < shots.size(); i += 1) {
            var s = shots[i];
            if (s[4] == null) { continue; }
            var px = s[4] as Array<Float>;
            var py = s[5] as Array<Float>;
            var a = ArcheryUi.aimStart(px.size(), s[6]);
            var n = px.size();
            if (n - a < 2) { continue; }
            var mx = 0.0;
            var my = 0.0;
            for (var j = a; j < n; j += 1) {
                ArcheryUi.gridAdd(g, GRID, _floatSpan, px[j], py[j]);
                mx += px[j];
                my += py[j];
            }
            // movement from the float centroid into the release point (0, 0)
            bx -= mx / (n - a);
            by -= my / (n - a);
            _floatN += 1;
        }
        if (_floatN > 0) {
            _biasX = bx / _floatN;
            _biasY = by / _floatN;
        }
        _float = ArcheryUi.gridSmooth(g, GRID);
    }

    private function drawFloat(dc) as Void {
        var h = dc.getHeight();
        var cx = dc.getWidth() / 2.0;
        var cy = h * 0.52;
        var half = h * 0.30;
        var sk = ArcheryUi.scale(dc);
        title(dc, "AIM FLOAT");
        if (_float == null) {
            buildFloat();
        }
        if (_floatN == 0) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_XTINY, "No aim data", ArcheryUi.CENTER);
            return;
        }
        ArcheryUi.drawGrid(dc, _float, GRID, cx, cy, 2 * half);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(cx - half, cy - half, 2 * half, 2 * half);
        dc.drawLine(cx - half, cy, cx + half, cy);
        dc.drawLine(cx, cy - half, cx, cy + half);

        // arrow: from where the aim floated (on average) to the release point
        var k = half / _floatSpan;
        var x0 = cx - _biasX * k;
        var y0 = cy + _biasY * k;
        dc.setPenWidth((2 * sk + 0.5).toNumber());
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x0, y0, cx, cy);
        var ang = Math.atan2(cy - y0, cx - x0);
        var hl = 7 * sk;
        dc.drawLine(cx, cy, cx - hl * Math.cos(ang - 0.5), cy - hl * Math.sin(ang - 0.5));
        dc.drawLine(cx, cy, cx - hl * Math.cos(ang + 0.5), cy - hl * Math.sin(ang + 0.5));
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 3 * sk);

        var mag = Math.sqrt(_biasX * _biasX + _biasY * _biasY);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY,
            "drift " + mag.format("%.1f") + " cm " + direction(_biasX, _biasY), ArcheryUi.CENTER);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.18, Graphics.FONT_XTINY,
            "box +-" + _floatSpan.format("%.0f") + " cm", ArcheryUi.CENTER);
    }

    private function direction(x, y) {
        if (Math.sqrt(x * x + y * y) < 0.3) { return "(none)"; }
        var names = ["right", "up-right", "up", "up-left", "left", "down-left", "down", "down-right"];
        var a = Math.atan2(y, x) * 180.0 / Math.PI;
        if (a < 0) { a += 360.0; }
        return names[((a + 22.5) / 45.0).toNumber() % 8];
    }

    // ------------------------------------------------------------ pages 4+

    private function drawShot(dc, i) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2.0;
        var cy = h * 0.50;
        var r = h * 0.33;
        var sk = ArcheryUi.scale(dc);
        var s = (_m.shots as Array<Array>)[i];
        var k = r / (_m.faceCm / 2.0);
        // hit point on screen; when zoomed the view is centred on it
        var hx = cx + s[0] * k;
        var hy = cy - s[1] * k;
        var fx = cx;
        var fy = cy;
        if (zoom) {
            k = k * 3;
            fx = cx - s[0] * k;
            fy = cy + s[1] * k;
            hx = cx;
            hy = cy;
        }
        ArcheryUi.drawRings(dc, fx, fy, r * (zoom ? 3 : 1), true);

        var appr = 0.0;
        var aim = 0.0;
        if (s[4] != null) {
            var px = s[4] as Array<Float>;
            var py = s[5] as Array<Float>;
            var n = px.size();
            var a = ArcheryUi.aimStart(n, s[6]);
            var pen = (2 * sk + 0.5).toNumber();
            ArcheryUi.drawPath(dc, px, py, 0, a + 1, hx, hy, k, Graphics.COLOR_PURPLE, pen);
            ArcheryUi.drawPath(dc, px, py, a, n, hx, hy, k, Graphics.COLOR_BLUE, pen);
            appr = a * s[6];
            aim = (n - 1 - a) * s[6];
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(hx, hy, 4 * sk);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(hx, hy, 3 * sk);

        // black bands so the texts stay readable over the path
        var C = ArcheryUi.CENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, 0, w, h * 0.15);
        dc.fillRectangle(0, h * 0.80, w, h * 0.20);
        title(dc, "SHOT " + (i + 1).toString() + "  " + ArcheryUi.scoreLabel(s[2])
            + ((zoom) ? "  x3" : ""));
        if (s[4] == null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.85, Graphics.FONT_XTINY, "no aim data", C);
            return;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.845, Graphics.FONT_XTINY,
            "AIM " + ArcheryUi.moa(s[7], s[8], _m.distM).format("%.1f") + " MOA", C);
        dc.setColor(Graphics.COLOR_PURPLE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 4, h * 0.905, Graphics.FONT_XTINY, "appr " + appr.format("%.1f") + "s",
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 4, h * 0.905, Graphics.FONT_XTINY, "aim " + aim.format("%.1f") + "s",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function zeros() as Array<Float> {
        var g = new [GRID * GRID] as Array<Float>;
        for (var i = 0; i < GRID * GRID; i += 1) {
            g[i] = 0.0;
        }
        return g;
    }
}

class ReportDelegate extends WatchUi.BehaviorDelegate {

    private var _v;
    private var _exitOnBack;

    // exitOnBack = true after Save: BACK closes the app.
    function initialize(view, exitOnBack) {
        BehaviorDelegate.initialize();
        _v = view;
        _exitOnBack = exitOnBack;
    }

    function onNextPage() as Boolean {
        _v.move(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _v.move(-1);
        return true;
    }

    function onSelect() as Boolean {
        _v.move(1);
        return true;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_v.page >= 4) {
            _v.zoom = !_v.zoom;
            WatchUi.requestUpdate();
        }
        return true;
    }

    function onBack() as Boolean {
        if (_exitOnBack) {
            System.exit();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
