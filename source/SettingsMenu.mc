import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch setup, available before the activity starts (UP button).
// Values are saved to the app properties, so they match the phone settings.

function faces() as Array<Number> { return [122, 80, 60, 40]; }
function distances() as Array<Number> { return [18, 30, 50, 70, 90]; }
function gains() as Array<Number> { return [100, 50, 30]; }

function openSettingsMenu(model) as Void {
    var m = new WatchUi.Menu2({ :title => "Setup" });
    m.addItem(new WatchUi.MenuItem("Distance", distLabel(model), :dist, null));
    m.addItem(new WatchUi.MenuItem("Target face", faceLabel(model), :face, null));
    m.addItem(new WatchUi.MenuItem("Watch on", wristLabel(model), :wrist, null));
    m.addItem(new WatchUi.MenuItem("Drag precision", gainLabel(model), :gain, null));
    m.addItem(new WatchUi.ToggleMenuItem("Invert aim X", null, :invX,
        model.readProp("invertX", false), null));
    m.addItem(new WatchUi.ToggleMenuItem("Invert aim Y", null, :invY,
        model.readProp("invertY", false), null));
    WatchUi.pushView(m, new SettingsMenuDelegate(model), WatchUi.SLIDE_UP);
}

function distLabel(model) as String { return model.readProp("distanceM", 70).toString() + " m"; }
function faceLabel(model) as String { return model.readProp("targetFace", 122).toString() + " cm"; }
function wristLabel(model) as String {
    return (model.readProp("watchWrist", 0) == 0) ? "Left wrist" : "Right wrist";
}
function gainLabel(model) as String {
    var g = model.readProp("dragPrecision", 100);
    return (g >= 100) ? "Under finger" : (g.toString() + " %");
}

// Next value in the list after the current one (wraps around).
function nextIn(list as Array<Number>, cur) as Number {
    for (var i = 0; i < list.size(); i += 1) {
        if (list[i] == cur) {
            return list[(i + 1) % list.size()];
        }
    }
    return list[0];
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _m;

    function initialize(model) {
        Menu2InputDelegate.initialize();
        _m = model;
    }

    // Selecting an item steps to its next value.
    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        var P = Application.Properties;
        if (id == :dist) {
            P.setValue("distanceM", $.nextIn($.distances(), _m.readProp("distanceM", 70)));
            item.setSubLabel($.distLabel(_m));
        } else if (id == :face) {
            P.setValue("targetFace", $.nextIn($.faces(), _m.readProp("targetFace", 122)));
            item.setSubLabel($.faceLabel(_m));
        } else if (id == :wrist) {
            P.setValue("watchWrist", 1 - _m.readProp("watchWrist", 0));
            item.setSubLabel($.wristLabel(_m));
        } else if (id == :gain) {
            P.setValue("dragPrecision", $.nextIn($.gains(), _m.readProp("dragPrecision", 100)));
            item.setSubLabel($.gainLabel(_m));
        } else if (id == :invX) {
            P.setValue("invertX", (item as WatchUi.ToggleMenuItem).isEnabled());
        } else if (id == :invY) {
            P.setValue("invertY", (item as WatchUi.ToggleMenuItem).isEnabled());
        }
        _m.loadSettings();
        WatchUi.requestUpdate();
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
