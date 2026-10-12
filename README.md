# Archery Target — Connect IQ app for Garmin smartwatches with gyroscope and touchscreen

A Connect IQ device app that records your archery activity: arrow positions on a
touch target, heart rate, respiration rate and bow-arm aim movement (X/Y) during each hold.

## Controls
| Screen   | Key / gesture | Action |
|----------|---------------|--------|
| Before start | UP (or hold UP) | setup: distance, face, wrist, drag precision, invert X/Y |
| Activity | START         | start / pause (pause opens Resume · Report · Save · Discard) |
| Activity | —             | the target opens by itself (with a buzz) when a release is detected |
| Activity | LAP (BACK)    | open the target manually (if a release was not detected) |
| Activity | UP / DOWN     | switch page: main (score + HR zone graph) ↔ last hold (X/Y aim traces) |
| Report   | UP / DOWN, START | pages: summary · hits heat map · aim float heat map · one page per arrow |
| Report   | tap (arrow page) | zoom ×3 around the hit |
| Report   | BACK          | after Save: close the app |
| Target   | touch + drag  | show and move the hit point |
| Target   | lift finger   | point fixed, score + hold time shown, auto-confirmed after 1.5 s |
| Target   | LAP or START  | confirm immediately; before touching = cancel |

## Hold detection (watch on the bow arm)
- **Arm up**: forearm within ~30° of horizontal for 0.4 s → recording of aim data starts.
- **Release**: acceleration shock > 1.5 g after at least 1 s of hold → hold time = arm up → release.
- **Arm down**: forearm steep again for 0.3 s → hold ends (if no release was detected, the hold
  time runs until the arm went down and the page shows "no release").
- Aim X/Y: gyroscope rotation about the vertical axis (left/right) and the lateral axis (up/down),
  converted to cm at the shooting distance. The gyro bias is learned while the arm is down and still.
  Check once: swing the bow slowly to the right → X should go up; if not, enable *Invert aim X*
  (same for Y) in the settings. Thresholds are constants at the top of `source/AimTracker.mc`.

## What gets recorded (FIT developer fields, 16 = the Connect IQ maximum)
- Per second (charts): aim X / Y = signed offset of the aim from its recent centre (~1.5 s average),
  X + = left / − = right, Y + = up / − = down; 0 while the arm is down and during the first second
  after raising it. Heart rate and respiration rate are recorded natively by the watch.
- Per lap (= arrow): x, y, score, hold time, aim steadiness X / Y (RMS over the last 2 s before release).
- Session: arrows, total, group centre X / Y, average hold time, average steadiness X / Y.

## Report and aim paths
- After the release the gyroscope trace stops; the last 8 s before the release are kept
  (~10 Hz) as the arrow's aim path, relative to the aim at the release ("break").
- The path is drawn ending on the marked hit: purple = approach (until the aim last came within
  15 % of the face diameter of the break), blue = aim, red = break. This assumes the arrow
  landed where the bow pointed at release — wind, form and tuning make the real offset differ.
- Aim MOA = radial RMS of the aim in the last 2 s before release, as an angle (1 MOA ≈ 2 cm at 70 m).
- Aim float heat map: all "aim" samples relative to the release point; the arrow is the average
  movement from the float centroid into the release (the drift / bending tendency).
- Garmin Connect cannot show images: the path is also saved in each lap as `aim_path`
  (32 points, 0.2 s apart, 1/4 cm), and `tools/plot_shots.py activity.fit --face 122 --dist 70
  --out report.png` renders the same report on a computer.

## Spoken feedback
Garmin Connect's standard lap alert (lap time) is spoken after each arrow. Speaking the score
would need a companion phone app (not included).

## Settings (Connect IQ app on the phone, store/beta install only)
Face diameter, shooting distance, wrist, drag precision, invert X / Y.
