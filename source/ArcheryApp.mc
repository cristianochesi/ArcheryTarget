import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ArcheryApp extends Application.AppBase {

    private var _model;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        _model = new ArcheryModel();
    }

    // If the app is closed without Save/Discard, keep the arrows already shot.
    function onStop(state as Dictionary?) as Void {
        if (_model != null) {
            _model.onAppExit();
        }
    }

    function getInitialView() {
        var view = new MainView(_model);
        return [view, new MainDelegate(_model, view)];
    }
}
