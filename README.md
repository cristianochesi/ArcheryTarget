# Archery Target — Connect IQ app for Forerunner 955

A Connect IQ device app that records its own "Archery" activity: arrow positions on a
touch target, heart rate, respiration rate and bow-arm aim movement (X/Y) during each hold.

## Controls
| Screen   | Key / gesture | Action |
|----------|---------------|--------|
| Activity | START         | start / pause (pause opens Resume · Summary · Save · Discard) |
| Activity | LAP (BACK)    | open the target for the arrow just shot |
| Activity | UP / DOWN     | switch page: main (score + HR zone graph) ↔ last hold (X/Y aim traces) |
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

## What gets recorded (FIT developer fields, 15 of the 16 allowed)
- Per second (charts): aim X / Y = signed offset of the aim from its recent centre (~1.5 s average),
  X + = left / − = right, Y + = up / − = down; 0 while the arm is down and during the first second
  after raising it. Heart rate and respiration rate are recorded natively by the watch.
- Per lap (= arrow): x, y, score, hold time, aim steadiness X / Y (RMS over the last 2 s before release).
- Session: arrows, total, group centre X / Y, average hold time, average steadiness X / Y.

## Spoken feedback
Connect IQ apps cannot produce speech. After each arrow the watch sends
`{"score", "hold", "lap", "text"}` to the phone via `Communications.transmit`; a small companion
phone app is needed to read `text` aloud (not included yet). Without it the message is dropped.

## Settings (Connect IQ app on the phone, store/beta install only)
Face diameter, shooting distance, wrist, drag precision, invert X / Y.

## AI Usage declaration
This code has been generated, debugged and optimized with the help of Claude Opus 5.5 model
