import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// Full-screen target. Touch to show the hit point, drag to move it,
// lift the finger to fix it. The shot is confirmed automatically after
// CONFIRM_MS (touch again within that time to correct), or immediately
// with LAP/START. LAP before touching = cancel (no arrow recorded).
class TargetView extends WatchUi.View {

    const CONFIRM_MS = 1500;

    private var _m;
    private var _timer;
    private var _w = 0;
    private var _h = 0;
    private var _cx = 0.0;
    private var _cy = 0.0;
    private var _r = 1.0;

    private var _px = null;   // marker position (screen px)
    private var _py = null;
    private var _ax = 0;      // finger position at touch-down
    private var _ay = 0;
    private var _amx = 0.0;   // marker position at touch-down
    private var _amy = 0.0;
    private var _released = false;
    private var _done = false;
    private var _hold = null;     // hold (arm up -> release) that belongs to this arrow

    function initialize(model) {
        View.initialize();
        _m = model;
        _timer = new Timer.Timer();
        _hold = model.pendingHold();
        model.targetOpen = true;
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2.0;
        _cy = _h / 2.0;
        // leave the outer 10 % of the screen outside the face: that is the "miss" zone
        _r = ((_cx < _cy) ? _cx : _cy) * 0.90;
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        ArcheryUi.drawFace(dc, _cx, _cy, _r);

        // arrow number, written inside the white bottom rings
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _cy + _r * 0.9, Graphics.FONT_XTINY,
            "ARROW " + (_m.count() + 1).toString(), ArcheryUi.CENTER);

        if (_px != null) {
            if (_released) {
                drawAimPath(dc);
            }
            drawMarker(dc);
            if (_released) {
                drawBadge(dc);
            }
        }
    }

    // Crosshair across the whole screen so the point stays readable under the finger.
    private function drawMarker(dc) as Void {
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, _py, _w, _py);
        dc.drawLine(_px, 0, _px, _h);
        var k = ArcheryUi.scale(dc);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_px, _py, 6 * k);
        dc.setColor(Graphics.COLOR_PINK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_px, _py, 4 * k);
    }

    // Aim path of this arrow, ending (the break) on the marked hit point.
    private function drawAimPath(dc) as Void {
        if (_hold == null || _hold[:px] == null) { return; }
        var px = _hold[:px] as Array<Float>;
        var py = _hold[:py] as Array<Float>;
        var n = px.size();
        var k = _r / (_m.faceCm / 2.0);
        var a = ArcheryUi.aimStart(n, _hold[:pdt]);
        var pen = (2 * ArcheryUi.scale(dc) + 0.5).toNumber();
        ArcheryUi.drawPath(dc, px, py, 0, a + 1, _px, _py, k, Graphics.COLOR_PURPLE, pen);
        ArcheryUi.drawPath(dc, px, py, a, n, _px, _py, k, Graphics.COLOR_DK_BLUE, pen);
    }

    // Score, hold time and x/y, drawn on the half of the target opposite to the marker.
    private function drawBadge(dc) as Void {
        var scoreTxt = ArcheryUi.scoreLabel(currentScore());
        var holdTxt = (_hold == null) ? "hold --" : "hold " + _hold[:hold].format("%.1f") + " s";
        var xyTxt = "x" + ArcheryUi.signed(xCm()) + " y" + ArcheryUi.signed(yCm());

        // size the box from the device fonts so it fits on every screen
        var fBig = Graphics.FONT_MEDIUM;
        var fSmall = Graphics.FONT_XTINY;
        var hBig = dc.getFontHeight(fBig);
        var hSmall = dc.getFontHeight(fSmall);
        var pad = (6 * ArcheryUi.scale(dc)).toNumber();
        var tw = dc.getTextWidthInPixels(xyTxt, fSmall);
        var t2 = dc.getTextWidthInPixels(holdTxt, fSmall);
        if (t2 > tw) { tw = t2; }
        var bw = tw + 4 * pad;
        var bh = hBig + 2 * hSmall + 2 * pad;
        var by = (_py > _cy) ? _cy - _r * 0.5 : _cy + _r * 0.5;
        var top = by - bh / 2;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRoundedRectangle(_cx - bw / 2, top, bw, bh, 2 * pad);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, top + pad + hBig / 2, fBig, scoreTxt, ArcheryUi.CENTER);
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, top + pad + hBig + hSmall / 2, fSmall, holdTxt, ArcheryUi.CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, top + pad + hBig + hSmall * 3 / 2, fSmall, xyTxt, ArcheryUi.CENTER);
    }

    // ------------------------------------------------------------ touch input

    function touchDown(x, y) as Void {
        if (_done) { return; }
        _timer.stop();
        _released = false;
        // In fine mode a second touch moves the existing marker instead of jumping.
        if (_px == null || _m.dragGain >= 1.0) {
            _px = clampX(x.toFloat());
            _py = clampY(y.toFloat());
        }
        _ax = x;
        _ay = y;
        _amx = _px;
        _amy = _py;
        WatchUi.requestUpdate();
    }

    function touchMove(x, y) as Void {
        if (_done) { return; }
        if (_px == null) {
            touchDown(x, y);
            return;
        }
        _px = clampX(_amx + _m.dragGain * (x - _ax));
        _py = clampY(_amy + _m.dragGain * (y - _ay));
        WatchUi.requestUpdate();
    }

    function touchUp() as Void {
        if (_done || _px == null) { return; }
        _released = true;
        _timer.stop();
        _timer.start(method(:confirm), CONFIRM_MS, false);
        WatchUi.requestUpdate();
    }

    // LAP / START on the target screen
    function lapPressed() as Void {
        if (_px == null) {
            _done = true;
            _m.targetOpen = false;
            WatchUi.popView(WatchUi.SLIDE_DOWN);   // cancel
        } else {
            confirm();
        }
    }

    function confirm() as Void {
        if (_done || _px == null) { return; }
        _done = true;
        _timer.stop();
        _m.recordShot(xCm(), yCm(), currentScore(), _hold);
        _m.targetOpen = false;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // ------------------------------------------------------------ geometry

    private function clampX(v) { return (v < 0) ? 0.0 : ((v > _w - 1) ? (_w - 1).toFloat() : v); }
    private function clampY(v) { return (v < 0) ? 0.0 : ((v > _h - 1) ? (_h - 1).toFloat() : v); }

    // px -> cm on the real face (y axis flipped: up = positive)
    private function xCm() { return ((_px - _cx) * (_m.faceCm / 2.0) / _r).toFloat(); }
    private function yCm() { return ((_cy - _py) * (_m.faceCm / 2.0) / _r).toFloat(); }

    private function currentScore() {
        return ArcheryUi.scoreFor(_px - _cx, _py - _cy, _r);
    }
}
