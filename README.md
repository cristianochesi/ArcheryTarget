# Archery Target — Connect IQ

A Connect IQ device app that records its own Archery activity: arrow positions on a
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
- The release kick of the bow arm (the samples just before the shock is detected) is cut off,
  and samples are averaged in 0.1 s blocks so hand tremor does not alias into zig-zags.
- The path is drawn ending on the marked hit: purple = approach (raise, draw, anchor),
  blue = aim = the last 2 s before the release (the same window as the aim MOA), red = break. This assumes the arrow
  landed where the bow pointed at release — wind, form and tuning make the real offset differ.
- Aim MOA = radial RMS of the aim in the last 2 s before release, as an angle (1 MOA ≈ 2 cm at 70 m).
- Aim float heat map: all "aim" samples relative to the release point; the arrow is the average
  movement from the float centroid into the release (the drift / bending tendency).
- Garmin Connect cannot show images: the path is also saved in each lap as `aim_path`
  (32 points, 0.2 s apart, 1/4 cm), and `tools/plot_shots.py activity.fit --dist 70 --out report.png` renders the same report on a
  computer. The face size is detected from the scores; `--dist` must be the distance that was set
  on the watch (the cm values were computed with it), otherwise the MOA values are off.

## Form metrics (main page, report, plot_shots.py)
All on the arrow-score scale: 10 − error / ring width (ring width = face / 20), clipped to 0–10.
- **ACC** accuracy: error = distance of the group centre from the target centre.
- **GRP** grouping: error = mean distance of the arrows from their own group centre.
- **STB** stability: error = aim wobble at the target (radial RMS, last 2 s before release).
- **FORM** = (ACC + GRP + STB) / 3.
Computed on the last end (6 arrows, 3 on the 40 cm face). Colours on the watch: green / red =
better / worse than the end before. Phase: WARM-UP (or IMPROVING after 3 ends) when FORM rose by
≥ 0.4, FATIGUE when it fell by ≥ 0.4 and is ≥ 0.4 below the best end, otherwise STABLE.
This is not an official archery standard (score, X count and group size are); it is a transparent
combination of the three. STB depends on the distance setting being right.

## Aiming detection
- RAISED = arm up but moving (raise, draw, carrying); AIMING = arm up and turning < 30°/s for 0.5 s.
  The per-second aim charts only record while AIMING.
- Only the last 20 s of a hold are kept (rolling); holds over 30 s get no hold time
  (the aim data before the release is still used).
- A hold that ends without a detected release is never attached to an arrow.

## Spoken feedback
Garmin Connect's standard lap alert (lap time) is spoken after each arrow. Speaking the score
would need a companion phone app (not included).

## Settings (Connect IQ app on the phone, store/beta install only)
Face diameter, shooting distance, wrist, drag precision, invert X / Y.
