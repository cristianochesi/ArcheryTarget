import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Shared drawing / formatting helpers.
module ArcheryUi {

    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    const HR_HISTORY = 120;   // bars in the HR zone graph (one every 2 s = 4 min)

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
}
