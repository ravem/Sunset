import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

//! Solar data model used by the data field.
//!
//! Sunrise / sunset are taken from Garmin's Weather API (same values the watch
//! itself shows). If the API has no data, they are computed locally with the
//! NOAA solar position algorithm.
//!
//! The blue hour is always computed locally: it is the window in which the sun
//! sits between 4° and 6° below the horizon (the photographic definition).
//!
//! Everything runs on the watch: no phone / internet connection is needed.
//! The last GPS position is cached, so the times also keep working when the
//! watch has no fix (e.g. indoor activities) for up to a week.
class SunTimes {

    //! Sun elevation (degrees) for the start / end of the blue hour.
    private const BLUE_HIGH = -4.0;
    private const BLUE_LOW = -6.0;
    //! Standard sunrise elevation: refraction + solar radius.
    private const SUNRISE_ELEV = -0.833;
    //! How long a cached position may be reused (seconds).
    private const MAX_FIX_AGE = 7 * 24 * 3600;

    private const KEY_LAT = "lastLat";
    private const KEY_LON = "lastLon";
    private const KEY_TIME = "lastFix";

    //! Local minutes of day (0..1439); -1 means "unknown" (polar day/night).
    public var sunriseMin as Number;
    public var sunsetMin as Number;
    public var morningBlueStart as Number;
    public var morningBlueEnd as Number;
    public var eveningBlueStart as Number;
    public var eveningBlueEnd as Number;
    public var hasFix as Boolean;

    private var _lat;
    private var _lon;
    private var _dayKey as Number;
    private var _tzOffset as Number;
    private var _lastCompute as Number;

    public function initialize() {
        sunriseMin = -1;
        sunsetMin = -1;
        morningBlueStart = -1;
        morningBlueEnd = -1;
        eveningBlueStart = -1;
        eveningBlueEnd = -1;
        hasFix = false;
        _lat = null;
        _lon = null;
        _dayKey = -1;
        _tzOffset = 0;
        _lastCompute = 0;
    }

    //! Refresh the model. Cheap to call every second: it only recomputes when
    //! the day, the time zone or the position changed (or every 5 minutes).
    public function update() as Void {
        var info = Position.getInfo();
        var loc = (info != null) ? info.position : null;

        var lat;
        var lon;
        var cached = false;

        if (loc != null) {
            var deg = loc.toDegrees();
            lat = deg[0];
            lon = deg[1];
        } else {
            // No GPS fix: reuse the last known position (indoor activities).
            var sLat = Storage.getValue(KEY_LAT);
            var sLon = Storage.getValue(KEY_LON);
            var sTime = Storage.getValue(KEY_TIME);
            if (sLat == null || sLon == null || sTime == null) {
                return;
            }
            if ((Time.now().value() - (sTime as Number)) > MAX_FIX_AGE) {
                return;
            }
            lat = (sLat as Float).toDouble();
            lon = (sLon as Float).toDouble();
            cached = true;
        }

        var now = Time.now();
        var local = Gregorian.info(now, Time.FORMAT_SHORT);
        var utc = Gregorian.utcInfo(now, Time.FORMAT_SHORT);

        var tz = (local.hour * 60 + local.min) - (utc.hour * 60 + utc.min);
        if (tz > 720) {
            tz -= 1440;
        } else if (tz < -720) {
            tz += 1440;
        }

        var dayKey = (local.year as Number) * 10000 + (local.month as Number) * 100 + local.day;
        var nowSec = now.value();

        var moved = true;
        if (_lat != null && _lon != null) {
            moved = Math.abs(_lat - lat) > 0.02 || Math.abs(_lon - lon) > 0.02;
        }

        var stale = (_lastCompute == 0) || ((nowSec - _lastCompute) >= 300);
        if (!moved && (dayKey == _dayKey) && (tz == _tzOffset) && !stale) {
            return;
        }

        if (!cached) {
            Storage.setValue(KEY_LAT, lat.toFloat());
            Storage.setValue(KEY_LON, lon.toFloat());
            Storage.setValue(KEY_TIME, nowSec);
        }

        _lat = lat;
        _lon = lon;
        _dayKey = dayKey;
        _tzOffset = tz;
        _lastCompute = nowSec;
        hasFix = true;

        compute(local, lat, lon, tz, loc, now);
    }

    private function compute(local as Gregorian.Info, lat, lon, tz, loc, now) as Void {
        sunriseMin = -1;
        sunsetMin = -1;
        morningBlueStart = -1;
        morningBlueEnd = -1;
        eveningBlueStart = -1;
        eveningBlueEnd = -1;

        var latRad = Math.toRadians(lat);
        var doy = dayOfYear(local.year as Number, local.month as Number, local.day);
        var gamma = 2.0 * Math.PI / 365.0 * (doy - 1);

        // Solar declination (radians) and equation of time (minutes), NOAA.
        var decl = 0.006918
            - 0.399912 * Math.cos(gamma) + 0.070257 * Math.sin(gamma)
            - 0.006758 * Math.cos(2 * gamma) + 0.000907 * Math.sin(2 * gamma)
            - 0.002697 * Math.cos(3 * gamma) + 0.001480 * Math.sin(3 * gamma);
        var eqtime = 229.18 * (0.000075
            + 0.001868 * Math.cos(gamma) - 0.032077 * Math.sin(gamma)
            - 0.014615 * Math.cos(2 * gamma) - 0.040849 * Math.sin(2 * gamma));

        // Solar noon in UTC minutes of the day.
        var solarNoon = 720.0 - 4.0 * lon - eqtime;

        // Sunrise / sunset: Garmin data first (needs a live fix), formula as fallback.
        var rise = null;
        var set = null;
        if (loc != null) {
            rise = Weather.getSunrise(loc, now);
            set = Weather.getSunset(loc, now);
        }

        var hRise = hourAngle(latRad, decl, SUNRISE_ELEV);
        if (rise != null) {
            sunriseMin = momentToLocalMin(rise);
        } else if (hRise >= 0.0) {
            sunriseMin = utcToLocalMin(solarNoon - 4.0 * hRise, tz);
        }

        if (set != null) {
            sunsetMin = momentToLocalMin(set);
        } else if (hRise >= 0.0) {
            sunsetMin = utcToLocalMin(solarNoon + 4.0 * hRise, tz);
        }

        // Blue hour windows.
        var hLow = hourAngle(latRad, decl, BLUE_LOW);
        var hHigh = hourAngle(latRad, decl, BLUE_HIGH);
        if (hLow >= 0.0 && hHigh >= 0.0) {
            morningBlueStart = utcToLocalMin(solarNoon - 4.0 * hLow, tz);
            morningBlueEnd = utcToLocalMin(solarNoon - 4.0 * hHigh, tz);
            eveningBlueStart = utcToLocalMin(solarNoon + 4.0 * hHigh, tz);
            eveningBlueEnd = utcToLocalMin(solarNoon + 4.0 * hLow, tz);
        }
    }

    //! Hour angle (degrees) at which the sun reaches the given elevation.
    //! Returns -1.0 when that elevation is never reached (polar day/night).
    private function hourAngle(latRad, decl, elevDeg) {
        var cosH = (Math.sin(Math.toRadians(elevDeg)) - Math.sin(latRad) * Math.sin(decl))
            / (Math.cos(latRad) * Math.cos(decl));
        if (cosH > 1.0 || cosH < -1.0) {
            return -1.0;
        }
        return Math.toDegrees(Math.acos(cosH));
    }

    private function utcToLocalMin(utcMin, tz) as Number {
        var m = Math.round(utcMin).toNumber() + tz;
        return ((m % 1440) + 1440) % 1440;
    }

    private function momentToLocalMin(m as Time.Moment) as Number {
        var info = Gregorian.info(m, Time.FORMAT_SHORT);
        return info.hour * 60 + info.min;
    }

    private function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cum = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
        var doy = cum[month - 1] + day;
        var leap = (year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0));
        if (leap && month > 2) {
            doy += 1;
        }
        return doy;
    }
}
