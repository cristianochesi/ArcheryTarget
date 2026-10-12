import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// Page 0: timer, score, arrows, HR / respiration and the HR zone graph.
// Page 1: last hold - hold time and the X / Y aim "oscilloscope".
// UP / DOWN (or swipe) switch page. Redrawn every second by the model.
class MainView extends WatchUi.View {

    const TRACE_WINDOW_S = 4;

    var page = 0;
    private var _m;

    function initialize(model) {
        View.initialize();
        _m = model;
    }

    function onShow() as Void {
        _m.mainVisible = true;
    }

    function onHide() as Void {
        _m.mainVisible = false;
    }

    function nextPage() as Void {
        page = (page + 1) % 2;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (page == 0) {
            drawMain(dc);
        } else {
            drawHold(dc);
        }
    }

    // ------------------------------------------------------------ page 0

    private function drawMain(dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var C = ArcheryUi.CENTER;

        var status = "START  |  UP = SETUP";
        var sc = Graphics.COLOR_LT_GRAY;
        if (_m.isRecording()) {
            if (_m.tracker.isUp) {
                status = "AIMING";
                sc = Graphics.COLOR_BLUE;
            } else {
                status = "READY  |  LAP = MARK";
                sc = Graphics.COLOR_GREEN;
            }
        } else if (_m.hasSession()) {
            status = "PAUSED";
            sc = Graphics.COLOR_ORANGE;
        }
        dc.setColor(sc, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.10, Graphics.FONT_XTINY, status, C);

        var info = Activity.getActivityInfo();
        var ms = (info != null) ? info.timerTime : null;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.20, Graphics.FONT_SMALL, ArcheryUi.formatTime(ms), C);

        dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.33, Graphics.FONT_NUMBER_MILD, _m.total.toString(), C);

        var n = _m.count();
        var avg = (n > 0) ? _m.avgScore().format("%.1f") : "--";
        var last = (_m.lastScore == null) ? "--" : ArcheryUi.scoreLabel(_m.lastScore);
        if (_m.hasSession()) {
            drawStat(dc, w * 0.25, h * 0.47, n.toString(), "ARROWS");
            drawStat(dc, cx,       h * 0.47, avg,          "AVG");
            drawStat(dc, w * 0.75, h * 0.47, last,         "LAST");
        } else {
            drawStat(dc, w * 0.30, h * 0.47, _m.distM.toNumber().toString() + " m", "DISTANCE");
            drawStat(dc, w * 0.70, h * 0.47, _m.faceCm.toNumber().toString() + " cm", "FACE");
        }

        // HR + respiration line
        var hr = _m.hr;
        var z = _m.hrZone(hr);
        var hrTxt = (hr == null) ? "HR --" : "HR " + hr.toString() + ((z > 0) ? "  Z" + z.toString() : "");
        var rr = _m.respRate;
        var rrTxt = (rr == null) ? "RR --" : "RR " + rr.toString();
        dc.setColor(zoneColor(z), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - 4, h * 0.645, Graphics.FONT_TINY, hrTxt, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + 10, h * 0.645, Graphics.FONT_TINY, rrTxt, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        drawHrGraph(dc, cx, h * 0.71, h * 0.90);
    }

    private function drawStat(dc, x, y, value, label) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_SMALL, value, ArcheryUi.CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + dc.getHeight() * 0.08, Graphics.FONT_XTINY, label, ArcheryUi.CENTER);
    }

    // Bars of the last 4 minutes of HR, coloured by zone (like the native HR graph).
    private function drawHrGraph(dc, cx, top, bottom) as Void {
        var bars = ArcheryUi.HR_HISTORY;
        var bw = ArcheryUi.scale(dc);             // bar width: 1 px on the FR955
        var gw = bars * bw;
        var x0 = cx - gw / 2;
        var gh = bottom - top;
        var lo = 60.0;
        var hi = 190.0;
        var zones = _m.hrZones;
        if (zones != null) {
            lo = zones[0] - 10.0;
            hi = zones[5].toFloat();
        }

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x0, bottom, x0 + gw, bottom);
        if (zones != null) {                       // zone boundaries
            for (var i = 1; i <= 4; i += 1) {
                var zy = bottom - gh * (zones[i] - lo) / (hi - lo);
                for (var x = x0; x < x0 + gw; x += 4 * bw) {
                    dc.drawPoint(x, zy);
                }
            }
        }

        var hist = _m.hrHist;
        var n = hist.size();
        var start = x0 + (bars - n) * bw;
        for (var i = 0; i < n; i += 1) {
            var v = hist[i];
            if (v <= 0) { continue; }
            var frac = (v - lo) / (hi - lo);
            if (frac < 0.05) { frac = 0.05; }
            if (frac > 1.0) { frac = 1.0; }
            var bh = gh * frac;
            dc.setColor(zoneColor(_m.hrZone(v)), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(start + i * bw, bottom - bh, (bw < 1) ? 1 : bw + 0.5, bh);
        }
    }

    private function zoneColor(z) {
        if (z == 1) { return Graphics.COLOR_LT_GRAY; }
        if (z == 2) { return Graphics.COLOR_BLUE; }
        if (z == 3) { return Graphics.COLOR_GREEN; }
        if (z == 4) { return Graphics.COLOR_ORANGE; }
        if (z == 5) { return Graphics.COLOR_RED; }
        return Graphics.COLOR_WHITE;
    }

    // ------------------------------------------------------------ page 1

    private function drawHold(dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var C = ArcheryUi.CENTER;

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.11, Graphics.FONT_XTINY, "LAST HOLD", C);

        var hold = _m.tracker.lastHold;
        if (!_m.tracker.hasGyro && _m.hasSession()) {
            dc.drawText(cx, h * 0.5, Graphics.FONT_XTINY, "No gyroscope data", C);
            return;
        }
        if (hold == null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h * 0.5, Graphics.FONT_XTINY, "Raise the bow to record", C);
            return;
        }

        var t = hold[:hold].format("%.1f") + " s";
        if (!hold[:released]) {
            t += "  no release";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.21, Graphics.FONT_SMALL, t, C);

        var gw = (w * 0.76).toNumber();
        var gx = (cx - gw / 2).toNumber();
        drawTrace(dc, hold[:xs], hold[:rate], gx, h * 0.30, gw, h * 0.20, "X up=left", -1.0, Graphics.COLOR_BLUE);
        drawTrace(dc, hold[:ys], hold[:rate], gx, h * 0.56, gw, h * 0.20, "Y up=up", 1.0, Graphics.COLOR_YELLOW);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.84, Graphics.FONT_XTINY,
            "last 2 s rms  X " + hold[:rmsX].format("%.1f") + "  Y " + hold[:rmsY].format("%.1f") + " cm", C);
    }

    // Last TRACE_WINDOW_S seconds of one axis, centred on its mean, auto-scaled.
    // sign = -1 flips the axis (X: left drawn upwards, like the Garmin Connect chart)
    private function drawTrace(dc, a, rate, x0, y0, gw, gh, name, sign, color) as Void {
        var n = a.size();
        var win = TRACE_WINDOW_S * rate;
        var from = (n > win) ? n - win : 0;
        var cnt = n - from;
        var mid = y0 + gh / 2;

        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawRectangle(x0, y0, gw, gh);
        dc.drawLine(x0, mid, x0 + gw, mid);
        if (cnt < 2) { return; }

        var mean = 0.0;
        for (var i = from; i < n; i += 1) { mean += a[i]; }
        mean = mean / cnt;
        var amp = 1.0;                          // at least +-1 cm full scale
        for (var i = from; i < n; i += 1) {
            var d = a[i] - mean;
            if (d < 0) { d = -d; }
            if (d > amp) { amp = d; }
        }

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((2 * ArcheryUi.scale(dc) + 0.5).toNumber());
        var px = x0;
        var py = mid;
        for (var i = from; i < n; i += 1) {
            var x = x0 + (i - from) * (gw - 1.0) / (cnt - 1);
            var y = mid - sign * (a[i] - mean) / amp * (gh / 2 - 2);
            if (i > from) {
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0 + 3, y0 + 1, Graphics.FONT_XTINY, name + " +-" + amp.format("%.1f"),
            Graphics.TEXT_JUSTIFY_LEFT);
    }
}
