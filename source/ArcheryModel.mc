import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Recording session, arrows, statistics, HR history and aim data.
// Arrow coordinates are in cm on the real face: x > 0 = right, y > 0 = up.
class ArcheryModel {

    const SPORT_ARCHERY_FIT = 79;   // FIT profile sport id "archery"
    const FIT_PATH_N = 32;          // aim-path points stored per arrow in the FIT file
    const FIT_PATH_DT = 0.2;        // seconds between them (last 6.4 s before the release)
    const FIT_PATH_SCALE = 4.0;     // stored as SINT16 in 1/4 cm

    var faceCm = 122.0;
    var dragGain = 1.0;
    var distM = 70.0;
    // [xCm, yCm, score, holdSec or -1, pathX, pathY, pathDt, rmsX, rmsY]  (path = null if no hold)
    var shots = [];
    var total = 0;
    var lastScore = null;
    var tracker;                    // AimTracker
    var hr = null;                  // current heart rate (bpm)
    var hrHist = [];                // last ArcheryUi.HR_HISTORY samples, 0 = no reading
    var hrZones = null;             // [z1 min, z1 max, z2 max, z3 max, z4 max, z5 max]
    var respRate = null;            // breaths/min
    var mainVisible = false;        // MainView on top (auto-open of the target only from there)
    var targetOpen = false;
    var hrAvg = 0;
    var hrMax = 0;
    var respAvg = 0.0;

    private var _session;
    private var _sec = 0;
    private var _usedHoldId = -1;
    private var _sumX = 0.0;
    private var _sumY = 0.0;
    private var _sumDist = 0.0;
    private var _holdN = 0;
    private var _sumHold = 0.0;
    private var _sumRmsX = 0.0;
    private var _sumRmsY = 0.0;
    private var _hrSum = 0;
    private var _hrN = 0;
    private var _rrSum = 0.0;
    private var _rrN = 0;
    private var _durationMs = 0;

    // FIT fields: ids must match resources/fit/fitcontributions.xml (16 = the maximum per app)
    private var _fPath;
    private var _fWobX;
    private var _fWobY;
    private var _fShotX;
    private var _fShotY;
    private var _fShotScore;
    private var _fHold;
    private var _fRmsX;
    private var _fRmsY;
    private var _fArrows;
    private var _fTotal;
    private var _fMeanX;
    private var _fMeanY;
    private var _fAvgHold;
    private var _fAvgRmsX;
    private var _fAvgRmsY;

    function initialize() {
        tracker = new AimTracker(70, true, false, false, method(:onSecond));
        tracker.onRelease = method(:onRelease);
        loadSettings();
        try {
            hrZones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        } catch (e) {
            hrZones = null;
        }
    }

    // (Re)reads the settings: at start-up and after a change in the on-watch menu.
    function loadSettings() as Void {
        faceCm = readProp("targetFace", 122).toFloat();
        dragGain = readProp("dragPrecision", 100).toFloat() / 100.0;
        distM = readProp("distanceM", 70).toFloat();
        tracker.configure(distM, readProp("watchWrist", 0) == 0,
            readProp("invertX", false), readProp("invertY", false));
    }

    function readProp(key, def) {
        try {
            var v = Application.Properties.getValue(key);
            if (v != null) {
                return v;
            }
        } catch (e) {
        }
        return def;
    }

    // ---------------------------------------------------------------- session

    function hasSession() {
        return _session != null;
    }

    function isRecording() {
        return _session != null && _session.isRecording();
    }

    function start() as Void {
        if (_session == null) {
            _session = createArcherySession();
            createFields();
            tracker.start();
        }
        if (!_session.isRecording()) {
            _session.start();
        }
    }

    // FIT sport 79 = "archery" (FIT SDK profile), the type the native Archery profile
    // records and Garmin Connect shows as Other > Archery. The Connect IQ enum has no
    // name for it yet, so the raw value is used; if the firmware refuses it, fall back
    // to a generic activity.
    private function createArcherySession() {
        try {
            return ActivityRecording.createSession({
                :name => "Archery",
                :sport => SPORT_ARCHERY_FIT as Activity.Sport,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        } catch (e) {
            return ActivityRecording.createSession({
                :name => "Archery",
                :sport => Activity.SPORT_GENERIC,
                :subSport => Activity.SUB_SPORT_GENERIC
            });
        }
    }

    function pause() as Void {
        if (isRecording()) {
            _session.stop();
        }
    }

    function save() as Void {
        captureDuration();
        tracker.stop();
        if (_session != null) {
            if (_session.isRecording()) {
                _session.stop();
            }
            _session.save();
            _session = null;
        }
    }

    function discard() as Void {
        tracker.stop();
        if (_session != null) {
            if (_session.isRecording()) {
                _session.stop();
            }
            _session.discard();
            _session = null;
        }
    }

    function durationMs() {
        if (_session != null) {
            captureDuration();
        }
        return _durationMs;
    }

    private function captureDuration() as Void {
        var info = Activity.getActivityInfo();
        if (info != null && info.timerTime != null) {
            _durationMs = info.timerTime;
        }
    }

    function onAppExit() as Void {
        if (_session == null) {
            tracker.stop();
        } else if (shots.size() > 0) {
            save();
        } else {
            discard();
        }
    }

    private function createFields() as Void {
        var rec = FitContributor.MESG_TYPE_RECORD;
        var lap = FitContributor.MESG_TYPE_LAP;
        var ses = FitContributor.MESG_TYPE_SESSION;
        var f = FitContributor.DATA_TYPE_FLOAT;
        var u16 = FitContributor.DATA_TYPE_UINT16;

        // respiration and heart rate are recorded natively by the watch
        _fPath = _session.createField("aim_path", 0, FitContributor.DATA_TYPE_SINT16,
            { :mesgType => lap, :units => "cm/4", :count => 2 * FIT_PATH_N });
        _fWobX      = field("aim_x",         1, f, rec, "cm");
        _fWobY      = field("aim_y",         2, f, rec, "cm");

        _fShotX     = field("shot_x",        3, f, lap, "cm");
        _fShotY     = field("shot_y",        4, f, lap, "cm");
        _fShotScore = field("shot_score",    5, FitContributor.DATA_TYPE_UINT8, lap, "pts");
        _fHold      = field("hold_time",     6, f, lap, "s");
        _fRmsX      = field("aim_rms_x",     7, f, lap, "cm");
        _fRmsY      = field("aim_rms_y",     8, f, lap, "cm");

        _fArrows    = field("arrows",        9, u16, ses, "arrows");
        _fTotal     = field("total_score",  10, u16, ses, "pts");
        _fMeanX     = field("mean_x",       11, f, ses, "cm");
        _fMeanY     = field("mean_y",       12, f, ses, "cm");
        _fAvgHold   = field("avg_hold",     13, f, ses, "s");
        _fAvgRmsX   = field("avg_aim_rms_x",14, f, ses, "cm");
        _fAvgRmsY   = field("avg_aim_rms_y",15, f, ses, "cm");
    }

    private function field(name, id, type, mesg, units) {
        return _session.createField(name, id, type, { :mesgType => mesg, :units => units });
    }

    // ---------------------------------------------------------------- 1 Hz tick
    // Called by AimTracker after every one-second sensor batch.

    function onSecond() as Void {
        _sec += 1;
        var info = Activity.getActivityInfo();
        hr = (info != null) ? info.currentHeartRate : null;
        if (_sec % 2 == 0) {
            hrHist.add((hr != null) ? hr : 0);
            if (hrHist.size() > ArcheryUi.HR_HISTORY) {
                hrHist = hrHist.slice(1, null);
            }
        }

        var am = ActivityMonitor.getInfo();
        if (am has :respirationRate) {
            respRate = am.respirationRate;
        }

        if (isRecording()) {
            if (hr != null && hr > 0) {
                _hrSum += hr;
                _hrN += 1;
                hrAvg = _hrSum / _hrN;
                if (hr > hrMax) { hrMax = hr; }
            }
            if (respRate != null && respRate > 0) {
                _rrSum += respRate;
                _rrN += 1;
                respAvg = _rrSum / _rrN;
            }
            // signed aim offset, 0 while the arm is down
            _fWobX.setData(tracker.aimX);
            _fWobY.setData(tracker.aimY);
        }
        WatchUi.requestUpdate();
    }

    function hrZone(v) {
        if (v == null || v <= 0 || hrZones == null) { return 0; }
        if (v < hrZones[0]) { return 0; }
        for (var i = 1; i <= 5; i += 1) {
            if (v <= hrZones[i]) { return i; }
        }
        return 5;
    }

    // ---------------------------------------------------------------- arrows

    // The hold (arm up -> release) not yet assigned to an arrow, or null.
    function pendingHold() {
        var h = tracker.lastHold;
        if (h == null || h[:id] == _usedHoldId) {
            return null;
        }
        return h;
    }

    // Release detected by the tracker: buzz and open the target to mark the hit.
    function onRelease() as Void {
        if (!isRecording() || !mainVisible || targetOpen) {
            return;
        }
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 150)]);
        }
        var v = new TargetView(self);
        WatchUi.pushView(v, new TargetDelegate(v), WatchUi.SLIDE_UP);
    }

    // Writes the lap fields, updates the summary and closes the lap.
    // h = the hold that belongs to this arrow (captured when the target opened), or null.
    function recordShot(x, y, score, h) as Void {
        var d = Math.sqrt(x * x + y * y).toFloat();
        if (h != null && h[:id] == _usedHoldId) {
            h = null;
        }
        var holdSec = -1.0;
        var rmsX = 0.0;
        var rmsY = 0.0;
        if (h != null) {
            _usedHoldId = h[:id];
            holdSec = h[:hold].toFloat();
            rmsX = h[:rmsX];
            rmsY = h[:rmsY];
            _holdN += 1;
            _sumHold += holdSec;
            _sumRmsX += rmsX;
            _sumRmsY += rmsY;
        }

        var px = null;
        var py = null;
        var pdt = 0.0;
        if (h != null && h[:px] != null && (h[:px] as Array).size() > 1) {
            px = h[:px];
            py = h[:py];
            pdt = h[:pdt];
        }
        shots.add([x, y, score, holdSec, px, py, pdt, rmsX, rmsY]);
        total += score;
        lastScore = score;
        _sumX += x;
        _sumY += y;
        _sumDist += d;

        if (_session == null) {
            return;
        }
        _fPath.setData(fitPath(px, py, pdt));
        _fShotX.setData(x);
        _fShotY.setData(y);
        _fShotScore.setData(score);
        _fHold.setData((holdSec > 0) ? holdSec : 0.0);
        _fRmsX.setData(rmsX);
        _fRmsY.setData(rmsY);

        _fArrows.setData(count());
        _fTotal.setData(total);
        _fMeanX.setData(meanX());
        _fMeanY.setData(meanY());
        if (_holdN > 0) {
            _fAvgHold.setData(_sumHold / _holdN);
            _fAvgRmsX.setData(_sumRmsX / _holdN);
            _fAvgRmsY.setData(_sumRmsY / _holdN);
        }
        if (_session.isRecording()) {
            _session.addLap();
        }
    }

    // Last FIT_PATH_N points of the path at FIT_PATH_DT spacing, interleaved x,y, oldest first,
    // in 1/4 cm; missing points = 32767 (FIT "invalid").
    private function fitPath(px, py, pdt) {
        var out = new [2 * FIT_PATH_N];
        for (var i = 0; i < 2 * FIT_PATH_N; i += 1) {
            out[i] = 32767;
        }
        if (px == null || pdt <= 0) {
            return out;
        }
        var n = px.size();
        for (var k = 0; k < FIT_PATH_N; k += 1) {
            var back = ((FIT_PATH_N - 1 - k) * FIT_PATH_DT / pdt + 0.5).toNumber();
            var i = n - 1 - back;
            if (i < 0) { continue; }
            out[2 * k] = clip16(px[i] * FIT_PATH_SCALE);
            out[2 * k + 1] = clip16(py[i] * FIT_PATH_SCALE);
        }
        return out;
    }

    private function clip16(v) {
        var n = (v < 0) ? (v - 0.5).toNumber() : (v + 0.5).toNumber();
        if (n > 32766) { return 32766; }
        if (n < -32767) { return -32767; }
        return n;
    }

    function count() {
        return shots.size();
    }

    private function mean(sum) {
        var n = shots.size();
        return (n > 0) ? (sum / n).toFloat() : 0.0;
    }

    function avgScore() { return mean(total.toFloat()); }
    function meanX()    { return mean(_sumX); }
    function meanY()    { return mean(_sumY); }
    function meanDist() { return mean(_sumDist); }
    function avgHold()  { return (_holdN > 0) ? (_sumHold / _holdN).toFloat() : 0.0; }
    function avgRmsX()  { return (_holdN > 0) ? (_sumRmsX / _holdN).toFloat() : 0.0; }
    function avgRmsY()  { return (_holdN > 0) ? (_sumRmsY / _holdN).toFloat() : 0.0; }
    function holdCount() { return _holdN; }
}
