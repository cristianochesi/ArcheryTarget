import Toybox.Lang;
import Toybox.WatchUi;

// START = start/pause, LAP (BACK/LAP key) = mark the arrow just shot,
// UP / DOWN = switch between the main page and the last-hold page.
class MainDelegate extends WatchUi.BehaviorDelegate {

    private var _m;
    private var _v;

    function initialize(model, view) {
        BehaviorDelegate.initialize();
        _m = model;
        _v = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER) {
            startStop();
            return true;
        }
        if (key == WatchUi.KEY_ESC || key == WatchUi.KEY_LAP) {
            return lap();
        }
        if (key == WatchUi.KEY_UP || key == WatchUi.KEY_DOWN) {
            _v.nextPage();
            return true;
        }
        return false;
    }

    function onSwipe(evt as WatchUi.SwipeEvent) as Boolean {
        var d = evt.getDirection();
        if (d == WatchUi.SWIPE_UP || d == WatchUi.SWIPE_DOWN) {
            _v.nextPage();
        }
        return true;
    }

    // Swallow taps so a brushed screen never starts/stops the activity.
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    private function startStop() as Void {
        if (_m.isRecording()) {
            _m.pause();
            $.openPauseMenu(_m);
        } else {
            _m.start();
        }
        WatchUi.requestUpdate();
    }

    private function lap() as Boolean {
        if (_m.isRecording()) {
            var v = new TargetView(_m);
            WatchUi.pushView(v, new TargetDelegate(v), WatchUi.SLIDE_UP);
            return true;
        }
        if (_m.hasSession()) {
            $.openPauseMenu(_m);
            return true;
        }
        return false;   // nothing recorded yet: BACK leaves the app
    }
}
