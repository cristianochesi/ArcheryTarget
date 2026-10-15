import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;

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
    const MAX_TRACE_S     = 20;     // rolling: only the LAST 20 s of a hold are kept
    const MAX_HOLD_S      = 30.0;   // longer "holds" are not a shot routine: no hold time
    const STEADY_DPS      = 30.0;   // aiming = arm up AND turning slower than this (deg/s) ...
    const STEADY_S        = 0.5;    // ... for at least this long (raise, draw, carrying = moving)
    const STEADY_WINDOW_S = 2.0;    // aim RMS over the last 2 s before the release
    const SETTLE_S        = 1.0;    // skip the first second after the arm comes up (the raise itself)
    const CENTRE_TAU_S    = 1.5;
    const PATH_MAX_S      = 8;
    const KICK_RATIO      = 4.0;    // a step this many times the typical one is the release kick
    const KICK_MAX_S      = 0.25;   // the kick is searched in the last 0.25 s before detection      // aim path kept for the report (last 8 s before the release)    // the "centre" of the aim is its average over the last ~1.5 s

    var isUp = false;
    var steady = false;    // arm up and still: really aiming
    var hasGyro = false;
    var lastHold = null;   // Dictionary: :id :hold :released :rmsX :rmsY :xs :ys :rate :px :py :pdt
    var onRelease = null;  // Method called (once per batch) right after a release is detected
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

    private var _calmCnt = 0;
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

    private var _releasedNow = false;
    private var _stopped = false;
    private var _gotReal = false;   // real sensor data has arrived
    private var _simTimer;
    private var _simWait = 0;
    private var _simT = 0.0;

    function initialize(distM, leftWrist, invertX, invertY, callback) {
        configure(distM, leftWrist, invertX, invertY);
        _cb = callback;
    }

    // Settings can change from the on-watch menu before the activity starts.
    function configure(distM, leftWrist, invertX, invertY) as Void {
        _distM = distM.toFloat();
        _wrist = leftWrist ? 1.0 : -1.0;
        _sx = invertX ? -1.0 : 1.0;
        _sy = invertY ? -1.0 : 1.0;
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
        _stopped = false;
        startSimulationFallback();
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
        _stopped = true;
        if (_simTimer != null) {
            _simTimer.stop();
        }
        if (_running) {
            Sensor.unregisterSensorDataListener();
            _running = false;
        }
    }

    // Called by the system once per second with a batch of samples.
    function onSensor(data as Sensor.SensorData) as Void {
        _gotReal = true;
        var acc = data.accelerometerData;
        if (acc == null) { return; }
        var gyr = data.gyroscopeData;
        if (gyr == null) {
            processBatch(acc.x, acc.y, acc.z, null, null, null);
        } else {
            processBatch(acc.x, acc.y, acc.z, gyr.x, gyr.y, gyr.z);
        }
    }

    // One second of samples: accelerometer in mg, gyroscope in deg/s (null = no gyroscope).
    private function processBatch(ax, ay, az, gx, gy, gz) as Void {
        hasGyro = (gx != null);
        var n = ax.size();
        var now = System.getTimer();
        var sx = 0.0;
        var sy = 0.0;
        var cnt = 0;

        for (var i = 0; i < n; i += 1) {
            var t = now - ((n - 1 - i) * 1000.0 * _dt).toNumber();
            var wx = 0.0;
            var wy = 0.0;
            var wz = 0.0;
            if (gx != null && i < gx.size()) {
                wx = gx[i].toFloat();
                wy = gy[i].toFloat();
                wz = gz[i].toFloat();
            }
            step(t, ax[i].toFloat(), ay[i].toFloat(), az[i].toFloat(), wx, wy, wz);

            if (isUp && !_released && hasGyro) {
                var px = xCm();
                var py = yCm();
                if (!_centreInit) {
                    _cx = px;
                    _cy = py;
                    _centreInit = true;
                }
                if (steady && (t - _holdStartMs) > (UP_DEBOUNCE_S + SETTLE_S) * 1000) {
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
        if (_releasedNow) {
            _releasedNow = false;
            if (onRelease != null) {
                onRelease.invoke();
            }
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

        if (hasGyro) {
            var cx = wx - _bx;
            var cy = wy - _by;
            var cz = wz - _bz;
            var sp = Math.sqrt(cx * cx + cy * cy + cz * cz);
            _calmCnt = (sp < STEADY_DPS) ? _calmCnt + 1 : 0;
            steady = (_calmCnt * _dt >= STEADY_S);
        } else {
            steady = true;
        }

        if (!_released) {
            if (hasGyro) {
                integrate(gn, wx - _bx, wy - _by, wz - _bz);
                if (_xs.size() >= MAX_TRACE_S * _rate) {
                    // drop the oldest second, keep the most recent MAX_TRACE_S
                    _xs = _xs.slice(_rate, null);
                    _ys = _ys.slice(_rate, null);
                }
                _xs.add(xCm());
                _ys.add(yCm());
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
            steady = false;
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
        steady = false;
        _calmCnt = 0;
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
        if (released) {
            _releasedNow = true;
            trimKick();
        }
        var n = _xs.size();
        var w = (STEADY_WINDOW_S * _rate).toNumber();
        if (w > n) { w = n; }
        var holdS = (endMs - _holdStartMs) / 1000.0;
        lastHold = {
            :id => _holdId,
            :hold => holdS,
            :holdValid => holdS <= MAX_HOLD_S,
            :released => released,
            :rmsX => rmsRange(_xs, n - w, n),
            :rmsY => rmsRange(_ys, n - w, n),
            :xs => _xs,
            :ys => _ys,
            :rate => _rate
        };
        buildPath();
    }

    // The bow arm kicks at the release a few hundredths of a second before the shock crosses
    // RELEASE_MG: cut those samples so the trace ends on the aim at the moment of release.
    private function trimKick() as Void {
        var n = _xs.size();
        var tail = (KICK_MAX_S * _rate).toNumber();
        if (n < tail + 5) { return; }
        var sum = 0.0;
        for (var i = 1; i < n - tail; i += 1) {
            sum += traceStep(i);
        }
        var limit = KICK_RATIO * sum / (n - tail - 1);
        if (limit < 0.5) { limit = 0.5; }
        var end = n - 1;
        // walk back through the kick (large steps) ...
        while (end > n - 1 - tail && traceStep(end) > limit) {
            end -= 1;
        }
        // ... and drop one more sample, still partly moving
        if (end < n - 1) {
            end -= 1;
        }
        if (end < n - 1) {
            _xs = _xs.slice(0, end + 1);
            _ys = _ys.slice(0, end + 1);
        }
    }

    private function traceStep(i as Number) as Float {
        var dx = (_xs[i] as Float) - (_xs[i - 1] as Float);
        var dy = (_ys[i] as Float) - (_ys[i - 1] as Float);
        return Math.sqrt(dx * dx + dy * dy).toFloat();
    }

    // Aim path for the report: the last PATH_MAX_S seconds at ~10 Hz, relative to the
    // aim at the moment of release (the "break"), in cm at the target. x > 0 = right, y > 0 = up.
    private function buildPath() as Void {
        var n = _xs.size();
        var step = (_rate / 10.0 + 0.5).toNumber();
        if (step < 1) { step = 1; }
        var maxPts = (PATH_MAX_S * _rate / step).toNumber();
        var cnt = (n + step - 1) / step;
        if (cnt > maxPts) { cnt = maxPts; }
        var px = new [cnt];
        var py = new [cnt];
        if (n > 0) {
            // each point = average of the `step` samples ending at it (removes the tremor
            // aliasing of plain decimation); the last point is the aim at release
            for (var k = 0; k < cnt; k += 1) {
                var i = n - 1 - (cnt - 1 - k) * step;
                var sx = 0.0;
                var sy = 0.0;
                var c = 0;
                for (var j = i; j > i - step && j >= 0; j -= 1) {
                    sx += _xs[j] as Float;
                    sy += _ys[j] as Float;
                    c += 1;
                }
                px[k] = sx / c;
                py[k] = sy / c;
            }
            var ex = px[cnt - 1];
            var ey = py[cnt - 1];
            for (var k = 0; k < cnt; k += 1) {
                px[k] = px[k] - ex;
                py[k] = py[k] - ey;
            }
        }
        lastHold[:px] = px;
        lastHold[:py] = py;
        lastHold[:pdt] = step.toFloat() / _rate;
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

    private function rmsRange(a as Array<Float>, from as Number, to as Number) {
        var n = to - from;
        if (n < 2) { return 0.0; }
        var s = 0.0;
        var ss = 0.0;
        for (var i = from; i < to; i += 1) {
            var v = a[i];
            s += v;
            ss += v * v;
        }
        return rms(s, ss, n);
    }

    // ---------------------------------------------------------------- simulator only
    // The simulator does not feed accelerometer/gyroscope data to apps. In debug builds
    // (Ctrl+F5), if no real sensor data has arrived after 3 s, synthetic shots are generated
    // in a 12 s cycle: 3 s arm down, raise, ~5.5 s aiming with tremor, release shock, lower.
    // Release builds (Build for Device, Export Project use -r) do not contain this code.
    (:debug)
    private function startSimulationFallback() as Void {
        _simWait = 0;
        _simT = 0.0;
        _simTimer = new Timer.Timer();
        _simTimer.start(method(:simTick), 1000, true);
    }

    (:release)
    private function startSimulationFallback() as Void {
    }

    (:debug)
    function simTick() as Void {
        if (_gotReal || _stopped) {
            _simTimer.stop();
            return;
        }
        _simWait += 1;
        if (_simWait <= 3) { return; }

        var n = _rate;
        var ax = new [n];
        var ay = new [n];
        var az = new [n];
        var gx = new [n];
        var gy = new [n];
        var gz = new [n];
        var w = 2.0 * Math.PI;
        for (var i = 0; i < n; i += 1) {
            var t = _simT + i * _dt;
            var cyc = t - 12.0 * (t / 12.0).toNumber();

            // 0 = arm hanging down, 1 = forearm horizontal
            var lift = 0.0;
            if (cyc >= 3.0 && cyc < 3.5) {
                lift = (cyc - 3.0) / 0.5;
            } else if (cyc >= 3.5 && cyc < 9.5) {
                lift = 1.0;
            } else if (cyc >= 9.5 && cyc < 10.0) {
                lift = 1.0 - (cyc - 9.5) / 0.5;
            }
            var a = lift * Math.PI / 2.0;
            // "up" along -X (towards the elbow) with the arm down, along +Z with the arm horizontal
            ax[i] = -1000.0 * Math.cos(a);
            ay[i] = 0.0;
            az[i] = 1000.0 * Math.sin(a);
            gx[i] = 0.0;
            gy[i] = 0.0;
            gz[i] = 0.0;

            if (cyc >= 3.5 && cyc < 9.0) {
                // aim X(t), Y(t) in degrees: 7 Hz / 6 Hz tremor plus a slow sway;
                // the gyroscope sees their derivatives (up = +Z, right = -Y)
                var dX = 0.05 * w * 7.0 * Math.cos(w * 7.0 * t) + 0.12 * w * 0.7 * Math.cos(w * 0.7 * t);
                var dY = 0.04 * w * 6.0 * Math.cos(w * 6.0 * t + 1.0) + 0.15 * w * 0.5 * Math.cos(w * 0.5 * t + 2.0);
                gz[i] = -dX;
                gy[i] = -dY;
            }
            if (cyc >= 9.0 && cyc < 9.0 + _dt) {
                ax[i] = ax[i] + 3000.0;   // release shock
            }
        }
        _simT += 1.0;
        processBatch(ax, ay, az, gx, gy, gz);
    }
}
