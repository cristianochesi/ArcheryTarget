import Toybox.Communications;
import Toybox.Lang;

// Connect IQ cannot speak by itself: this sends the text to a companion app on
// the phone, which reads it aloud with the phone's text-to-speech.
// Without the companion app the message is simply dropped.
module PhoneSpeaker {

    function say(score, holdSec, lapSec) as Void {
        var text = (score == 0) ? "Miss." : score.toString() + " points.";
        if (holdSec > 0) {
            text += " Hold " + holdSec.format("%.1f") + " seconds.";
        } else {
            text += " Lap " + lapSec.format("%.0f") + " seconds.";
        }
        try {
            Communications.transmit({
                "type" => "shot",
                "score" => score,
                "hold" => holdSec,
                "lap" => lapSec,
                "text" => text
            }, null, new SpeakListener());
        } catch (e) {
        }
    }
}

class SpeakListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }
    function onComplete() as Void {
    }
    function onError() as Void {
    }
}
