import Toybox.Lang;
import Toybox.WatchUi;

// Plain InputDelegate (not BehaviorDelegate) so swipes/drags are not turned
// into page changes or "back" while the arrow is being placed.
class TargetDelegate extends WatchUi.InputDelegate {

    private var _v;

    function initialize(view) {
        InputDelegate.initialize();
        _v = view;
    }

    function onDrag(evt as WatchUi.DragEvent) as Boolean {
        var c = evt.getCoordinates();
        var t = evt.getType();
        if (t == WatchUi.DRAG_TYPE_START) {
            _v.touchDown(c[0], c[1]);
        } else if (t == WatchUi.DRAG_TYPE_CONTINUE) {
            _v.touchMove(c[0], c[1]);
        } else {                       // DRAG_TYPE_STOP: finger lifted
            _v.touchMove(c[0], c[1]);
            _v.touchUp();
        }
        return true;
    }

    // A quick touch without movement
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        _v.touchDown(c[0], c[1]);
        _v.touchUp();
        return true;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    function onHold(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var k = evt.getKey();
        if (k == WatchUi.KEY_ESC || k == WatchUi.KEY_LAP || k == WatchUi.KEY_ENTER) {
            _v.lapPressed();
        }
        return true;
    }
}
