import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

//! Reading the activity history can be slow, so the answer is kept for a few minutes (and for the rest of the day once yes)
const MEDITATION_REFRESH_SECONDS = 300;
//! At most this many history entries are read. The history comes oldest first (on the fenix 9 its first entries were
//! weeks old), so today's activities are at its end and the whole of it has to be read.
const MEDITATION_HISTORY_LIMIT = 500;
//! The newest this many entries are described, when descriptions are asked for
const MEDITATION_DESCRIBED = 4;
//! Seconds from the Unix epoch to Garmin's (1989-12-31); some firmware reports activity start times from Garmin's epoch
const GARMIN_EPOCH_OFFSET = 631065600;

//! Whether a meditation activity has been recorded today, from UserProfile.getUserActivityHistory()
class MeditationCheck {

    public var sitToday as Boolean = false;
    //! Unix seconds of the last check, or null before the first
    public var checkedAt as Number or Null = null;
    public var queryMilliseconds as Number = 0;
    public var entryCount as Number = 0;
    public var error as String or Null = null;
    //! Descriptions of the newest few history entries, newest first, kept only when asked for (the probe shows them)
    public var entries as Array<String> = [] as Array<String>;
    private var _describeEntries as Boolean;

    public function initialize(describeEntries as Boolean) {
        _describeEntries = describeEntries;
    }

    public function refreshIfDue() as Void {
        var now = Time.now().value();
        var midnight = Time.today().value();
        var lastCheck = checkedAt;
        if (lastCheck != null && lastCheck >= midnight && lastCheck <= now) {
            if (sitToday || now - lastCheck < MEDITATION_REFRESH_SECONDS) {
                return;
            }
        }
        refresh(now, midnight);
    }

    //! Checks again on the next refreshIfDue()
    public function invalidate() as Void {
        if (!sitToday) {
            checkedAt = null;
        }
    }

    private function refresh(now as Number, midnight as Number) as Void {
        var started = System.getTimer();
        var found = false;
        var count = 0;
        var descriptions = [] as Array<String>;
        error = null;
        try {
            var iterator = UserProfile.getUserActivityHistory();
            var activity = iterator.next() as UserProfile.UserActivity or Null;
            while (activity != null && count < MEDITATION_HISTORY_LIMIT) {
                count++;
                var start = startSeconds(activity);
                if (activity.type == Activity.SPORT_MEDITATION && start != null && start >= midnight) {
                    found = true;
                }
                if (_describeEntries) {
                    descriptions.add(describe(activity, start));
                    if (descriptions.size() > MEDITATION_DESCRIBED) {
                        descriptions = descriptions.slice(1, null);
                    }
                }
                activity = iterator.next() as UserProfile.UserActivity or Null;
            }
        } catch (exception) {
            error = exception.getErrorMessage();
            if (error == null) {
                error = "error";
            }
        }
        sitToday = found;
        entryCount = count;
        entries = descriptions.reverse();
        checkedAt = now;
        queryMilliseconds = System.getTimer() - started;
    }

    //! Start time in Unix seconds, correcting a start time counted from Garmin's epoch
    private function startSeconds(activity as UserProfile.UserActivity) as Number or Null {
        var startTime = activity.startTime;
        if (startTime == null) {
            return null;
        }
        var seconds = startTime.value();
        return seconds < 1000000000 ? seconds + GARMIN_EPOCH_OFFSET : seconds;
    }

    //! "MEDITATION Sun 8 07:12 2m" or "type 1 Sun 8 07:12 45m"; "*" marks a start time counted from Garmin's epoch
    private function describe(activity as UserProfile.UserActivity, start as Number or Null) as String {
        var type = activity.type;
        var text = type == Activity.SPORT_MEDITATION ? "MEDITATION" : "type " + (type == null ? "?" : type.format("%d"));
        if (start != null) {
            var info = Gregorian.info(new Time.Moment(start), Time.FORMAT_MEDIUM);
            text += " " + info.day_of_week + " " + info.day + " " + (info.hour as Number).format("%02d") + ":" + (info.min as Number).format("%02d");
        }
        var duration = activity.duration;
        if (duration != null) {
            text += " " + (duration.value() / 60).format("%d") + "m";
        }
        var startTime = activity.startTime;
        if (startTime != null && startTime.value() < 1000000000) {
            text += "*";
        }
        return text;
    }
}
