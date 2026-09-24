import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

function openPauseMenu(model) as Void {
    var menu = new WatchUi.Menu2({ :title => "Paused" });
    menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
    menu.addItem(new WatchUi.MenuItem("Summary",
        model.count().toString() + " arrows, " + model.total.toString() + " pts", :summary, null));
    menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
    menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
    WatchUi.pushView(menu, new PauseMenuDelegate(model), WatchUi.SLIDE_UP);
}

class PauseMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _m;

    function initialize(model) {
        Menu2InputDelegate.initialize();
        _m = model;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            _m.start();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :summary) {
            WatchUi.pushView(new SummaryView(_m), new WatchUi.BehaviorDelegate(), WatchUi.SLIDE_LEFT);
        } else if (id == :save) {
            _m.save();
            System.exit();
        } else if (id == :discard) {
            WatchUi.pushView(new WatchUi.Confirmation("Discard session?"),
                new DiscardDelegate(_m), WatchUi.SLIDE_IMMEDIATE);
        }
    }
}

class DiscardDelegate extends WatchUi.ConfirmationDelegate {

    private var _m;

    function initialize(model) {
        ConfirmationDelegate.initialize();
        _m = model;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        if (response == WatchUi.CONFIRM_YES) {
            _m.discard();
            System.exit();
        }
        return true;
    }
}
