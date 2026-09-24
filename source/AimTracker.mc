import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;

// Watches the bow arm with the accelerometer + gyroscope.
//  - Arm UP   : forearm (watch X axis) close to horizontal for UP_DEBOUNCE_S
//  - Arm DOWN : forearm steep again for DOWN_DEBOUNCE_S
//  - Release  : acceleration shock while the arm is up
// While the arm is up (and until the release) the gyroscope is integrated into
// aim movement: X = left/right, Y = up/down, converted to cm at the target distance.
class AimTracker {

    const UP_MAX_COS      = 0.50;   // forearm within ~30 deg of horizontal
    const DOWN_MIN_COS    = 0.80;   // forearm steeper than ~37 deg from vertical
    const UP_DEBOUNCE_S   = 0.40;
    const DOWN_DEBOUNCE_S = 0.30;
    const RELEASE_MG      = 1500.0; // | |a| - 1 g | above this = release shock
    const MIN_HOLD_S      = 1.0;    // shocks in the first second of a hold are ignored
    const MAX_TRACE_S     = 20;
    const STEADY_WINDOW_S = 2.0;    // aim RMS over the last 2 s before the release
    const SETTLE_S        = 1.0;    // skip the first second after the arm comes up (the raise itself)
    const CENTRE_TAU_S    = 1.5;    // the "centre" of the aim is its average over the last ~1.5 s

    var isUp = false;
    var hasGyro = false;
    var lastHold = null;   // Dictionary: :id :hold :released :rmsX :rmsY :xs :ys :rate
    // Signed aim offset during the last second, relative to the recent aim centre (cm at target).
    // aimX > 0 = LEFT, < 0 = right; aimY > 0 = up, < 0 = down. 0 while the arm is down.
    var aimX = 0.0;
    var aimY = 0.0;

    private var _running = false;
    private var _cb;
    private var _rate = 25;
    private var _dt = 0.04;
    private var _alpha = 0.2;
    private var _distM = 70.0;
    private var _wrist = 1.0;     // +1 watch on left wrist, -1 on right wrist
    private var _sx = 1.0;        // axis inversion from settings
    private var _sy = 1.0;

    private var _gx = 0.0;        // low-passed acceleration (mg) = "up" direction
    private var _gy = 0.0;
    private var _gz = 1000.0;
    private var _bx = 0.0;        // gyroscope bias (deg/s), learned with the arm still and down
    private var _by = 0.0;
    private var _bz = 0.0;

    private var _upCnt = 0;
    private var _downCnt = 0;
    private var _released = false;
    private var _done = false;
    private var _holdStartMs = 0;
    private var _aimX = 0.0;      // integrated aim angles (deg)
    private var _aimY = 0.0;
    private var _xs = [];
    private var _ys = [];
    private var _holdId = 0;
    private var _cx = 0.0;        // moving aim centre (cm)
    private var _cy = 0.0;
    private var _centreInit = false;
    private var _centreK = 0.03;

    function initialize(distM, leftWrist, invertX, invertY, callback) {
        _distM = distM.toFloat();
        _wrist = leftWrist ? 1.0 : -1.0;
        _sx = invertX ? -1.0 : 1.0;
        _sy = invertY ? -1.0 : 1.0;
        _cb = callback;
    }

    function start() as Void {
        if (_running) { return; }
        var maxRate = 25;
        try {
            maxRate = Sensor.getMaxSampleRate();
        } catch (e) {
        }
        _rate = (maxRate > 50) ? 50 : maxRate;
        _dt = 1.0 / _rate;
        _alpha = _dt / (0.15 + _dt);
        _centreK = _dt / (CENTRE_TAU_S + _dt);
        try {
            Sensor.registerSensorDataListener(method(:onSensor), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => _rate },
                :gyroscope => { :enabled => true, :sampleRate => _rate }
            });
        } catch (e) {
            try {   // no gyroscope: arm up/down and release still work
                Sensor.registerSensorDataListener(method(:onSensor), {
                    :period => 1,
                    :accelerometer => { :enabled => true, :sampleRate => _rate }
                });
            } catch (e2) {
                return;
            }
        }
        _running = true;
    }

    function stop() as Void {
        if (_running) {
            Sensor.unregisterSensorDataListener();
            _running = false;
        }
    }

    // Called by the system once per second with a batch of samples.
    function onSensor(data as Sensor.SensorData) as Void {
        var acc = data.accelerometerData;
        if (acc == null) { return; }
        var gyr = data.gyroscopeData;
        hasGyro = (gyr != null);

        var n = acc.x.size();
        var now = System.getTimer();
        var sx = 0.0;
        var sy = 0.0;
        var cnt = 0;

        for (var i = 0; i < n; i += 1) {
            var t = now - ((n - 1 - i) * 1000.0 * _dt).toNumber();
            var wx = 0.0;
            var wy = 0.0;
            var wz = 0.0;
            if (gyr != null && i < gyr.x.size()) {
                wx = gyr.x[i].toFloat();
                wy = gyr.y[i].toFloat();
                wz = gyr.z[i].toFloat();
            }
            step(t, acc.x[i].toFloat(), acc.y[i].toFloat(), acc.z[i].toFloat(), wx, wy, wz);

            if (isUp && !_released && hasGyro) {
                var px = xCm();
                var py = yCm();
                if (!_centreInit) {
                    _cx = px;
                    _cy = py;
                    _centreInit = true;
                }
                if ((t - _holdStartMs) > (UP_DEBOUNCE_S + SETTLE_S) * 1000) {
                    sx += px - _cx;
                    sy += py - _cy;
                    cnt += 1;
                }
                _cx += _centreK * (px - _cx);
                _cy += _centreK * (py - _cy);
            }
        }

        if (cnt >= _rate / 2) {
            aimX = (-sx / cnt).toFloat();   // flipped: left is positive
            aimY = (sy / cnt).toFloat();
        } else {
            aimX = 0.0;
            aimY = 0.0;
        }
        if (_cb != null) {
            _cb.invoke();
        }
    }

    private function step(t, ax, ay, az, wx, wy, wz) as Void {
        _gx += _alpha * (ax - _gx);
        _gy += _alpha * (ay - _gy);
        _gz += _alpha * (az - _gz);
        var gn = Math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
        if (gn < 100.0) { return; }
        var cosF = ((_gx < 0) ? -_gx : _gx) / gn;
        var shock = Math.sqrt(ax * ax + ay * ay + az * az) - 1000.0;
        if (shock < 0) { shock = -shock; }

        if (!isUp) {
            // learn the gyroscope bias while the arm is down and still
            var wm = Math.sqrt(wx * wx + wy * wy + wz * wz);
            if (hasGyro && wm < 3.0 && shock < 100.0) {
                _bx += 0.02 * (wx - _bx);
                _by += 0.02 * (wy - _by);
                _bz += 0.02 * (wz - _bz);
            }
            _upCnt = (cosF < UP_MAX_COS) ? _upCnt + 1 : 0;
            if (_upCnt * _dt >= UP_DEBOUNCE_S) {
                beginHold(t);
            }
            return;
        }

        if (!_released) {
            if (hasGyro) {
                integrate(gn, wx - _bx, wy - _by, wz - _bz);
                if (_xs.size() < MAX_TRACE_S * _rate) {
                    _xs.add(xCm());
                    _ys.add(yCm());
                }
            }
            if (shock > RELEASE_MG && (t - _holdStartMs) > MIN_HOLD_S * 1000) {
                _released = true;
                finishHold(t, true);
            }
        }

        _downCnt = (cosF > DOWN_MIN_COS) ? _downCnt + 1 : 0;
        if (_downCnt * _dt >= DOWN_DEBOUNCE_S) {
            if (!_done) {
                finishHold(t - (DOWN_DEBOUNCE_S * 1000).toNumber(), false);
            }
            isUp = false;
            _upCnt = 0;
        }
    }

    // Rotation about the vertical axis = left/right aim, about the lateral axis = up/down.
    private function integrate(gn, wx, wy, wz) as Void {
        var ux = _gx / gn;
        var uy = _gy / gn;
        var uz = _gz / gn;
        // forward: forearm axis (watch X) projected on the horizontal plane
        var fx = 1.0 - ux * ux;
        var fy = -ux * uy;
        var fz = -ux * uz;
        var fn = Math.sqrt(fx * fx + fy * fy + fz * fz);
        if (fn < 0.1) { return; }
        fx = _wrist * fx / fn;
        fy = _wrist * fy / fn;
        fz = _wrist * fz / fn;
        // right = forward x up
        var rx = fy * uz - fz * uy;
        var ry = fz * ux - fx * uz;
        var rz = fx * uy - fy * ux;
        var yawRate = wx * ux + wy * uy + wz * uz;
        var pitchRate = wx * rx + wy * ry + wz * rz;
        _aimX -= yawRate * _dt;
        _aimY += pitchRate * _dt;
    }

    private function beginHold(t) as Void {
        isUp = true;
        _released = false;
        _done = false;
        _downCnt = 0;
        _holdStartMs = t - (UP_DEBOUNCE_S * 1000).toNumber();
        _aimX = 0.0;
        _aimY = 0.0;
        _xs = [];
        _ys = [];
        _centreInit = false;
    }

    private function finishHold(endMs, released) as Void {
        _done = true;
        _holdId += 1;
        var n = _xs.size();
        var w = (STEADY_WINDOW_S * _rate).toNumber();
        if (w > n) { w = n; }
        lastHold = {
            :id => _holdId,
            :hold => (endMs - _holdStartMs) / 1000.0,
            :released => released,
            :rmsX => rmsRange(_xs, n - w, n),
            :rmsY => rmsRange(_ys, n - w, n),
            :xs => _xs,
            :ys => _ys,
            :rate => _rate
        };
    }

    private function xCm() {
        return (_sx * _aimX * Math.PI / 180.0 * _distM * 100.0).toFloat();
    }

    private function yCm() {
        return (_sy * _aimY * Math.PI / 180.0 * _distM * 100.0).toFloat();
    }

    private function rms(sum, sumSq, n) {
        var m = sum / n;
        var v = sumSq / n - m * m;
        return (v > 0) ? Math.sqrt(v).toFloat() : 0.0;
    }

    private function rmsRange(a, from, to) {
        var n = to - from;
        if (n < 2) { return 0.0; }
        var s = 0.0;
        var ss = 0.0;
        for (var i = from; i < to; i += 1) {
            s += a[i];
            ss += a[i] * a[i];
        }
        return rms(s, ss, n);
    }
}
