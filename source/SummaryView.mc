import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch report: every arrow on the target, group centre, x/y offsets.
class SummaryView extends WatchUi.View {

    private var _m;

    function initialize(model) {
        View.initialize();
        _m = model;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2.0;
        var cy = h * 0.46;
        var r = h * 0.27;
        var C = ArcheryUi.CENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        ArcheryUi.drawFace(dc, cx, cy, r);

        var k = r / (_m.faceCm / 2.0);    // px per cm
        var shots = _m.shots as Array<Array>;
        for (var i = 0; i < shots.size(); i += 1) {
            var shot = shots[i] as Array<Float or Number>;
            var sx = cx + shot[0] * k;
            var sy = cy - shot[1] * k;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy, 3);
            dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy, 2);
        }

        var n = _m.count();
        if (n > 0) {
            var gx = cx + _m.meanX() * k;
            var gy = cy - _m.meanY() * k;
            dc.setPenWidth(3);
            dc.setColor(Graphics.COLOR_DK_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(gx - 7, gy, gx + 7, gy);
            dc.drawLine(gx, gy - 7, gx, gy + 7);
            dc.setPenWidth(1);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.12, Graphics.FONT_XTINY,
            n.toString() + " arrows  " + _m.total.toString() + " pts", C);
        dc.drawText(cx, h * 0.80, Graphics.FONT_XTINY,
            "X " + ArcheryUi.signed(_m.meanX()) + "  Y " + ArcheryUi.signed(_m.meanY()) + " cm", C);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.89, Graphics.FONT_XTINY,
            "dist " + _m.meanDist().format("%.1f") + " cm  hold " + _m.avgHold().format("%.1f") + " s", C);
    }
}
