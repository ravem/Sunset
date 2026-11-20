import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

//! Data field showing, on four stacked rows:
//!   1. current time (largest)
//!   2. sunrise
//!   3. sunset
//!   4. next blue hour window ("BLUE HOUR" inverted while it is happening)
//!
//! Everything is drawn in black / white / gray. The layout adapts to the area
//! the watch gives to the field, so it also works when it is not full screen.
class SunsetField extends WatchUi.DataField {

    private var _sun as SunTimes;
    private var _lastError as String?;

    public function initialize() {
        DataField.initialize();
        _sun = new SunTimes();
        _lastError = null;
    }

    //! Called once per second by the system.
    public function compute(info as Activity.Info) as Void {
        try {
            _sun.update();
        } catch (e instanceof Lang.Exception) {
            // Never let a data error kill the field: keep the clock running.
            _lastError = e.getErrorMessage();
        }
    }

    public function onUpdate(dc as Graphics.Dc) as Void {
        try {
            draw(dc);
        } catch (e instanceof Lang.Exception) {
            _lastError = e.getErrorMessage();
            drawFallback(dc);
        }
    }

    private function draw(dc as Graphics.Dc) as Void {
        _sun.update();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var minSide = (w < h) ? w : h;
        var s = minSide / 260.0;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var clock = System.getClockTime();
        var is24 = System.getDeviceSettings().is24Hour;

        var timeFont = pickTimeFont(minSide);
        var auxFont = pickAuxFont(minSide);
        var sunFont = pickSunFont(minSide);
        var sunAuxFont = Graphics.FONT_XTINY;
        var blueFont = pickBlueFont(minSide);

        // Very small slot: time only.
        if (h < 100 || w < 100) {
            drawTime(dc, w / 2, h / 2, timeFont, auxFont, clock, is24);
            return;
        }

        var fourRows = (h >= 200);
        var threeRows = (h >= 140);

        var timeCY;
        var sunCY = 0;
        var riseCY = 0;
        var setCY = 0;
        var blueCY = 0;

        if (fourRows) {
            timeCY = h * 0.20;
            riseCY = h * 0.42;
            setCY = h * 0.57;
            blueCY = h * 0.78;
        } else if (threeRows) {
            timeCY = h * 0.24;
            sunCY = h * 0.58;
            blueCY = h * 0.84;
        } else {
            timeCY = h * 0.33;
            sunCY = h * 0.68;
        }

        drawTime(dc, w / 2, timeCY, timeFont, auxFont, clock, is24);

        var iconR = Math.round(11 * s);
        if (iconR < 5) {
            iconR = 5;
        }
        var gap = Math.round(6 * s);
        if (gap < 4) {
            gap = 4;
        }

        if (fourRows) {
            drawSunLine(dc, w, riseCY, iconR, gap, sunFont, sunAuxFont, is24, true);
            drawSunLine(dc, w, setCY, iconR, gap, sunFont, sunAuxFont, is24, false);
        } else {
            drawSunRow(dc, w, sunCY, iconR, gap, sunFont, sunAuxFont, is24);
        }

        if (fourRows || threeRows) {
            drawBlueHour(dc, w, blueCY, clock, is24, blueFont);
        }
    }

    // ---------------------------------------------------------------- time

    private function drawTime(dc as Graphics.Dc, cx as Numeric, cy as Numeric,
                              font as Graphics.FontType, auxFont as Graphics.FontType,
                              clock as System.ClockTime, is24 as Boolean) as Void {
        var mainText;
        var auxText;

        if (is24) {
            mainText = pad2(clock.hour) + ":" + pad2(clock.min);
            auxText = pad2(clock.sec);
        } else {
            var h12 = clock.hour % 12;
            if (h12 == 0) {
                h12 = 12;
            }
            mainText = "" + h12 + ":" + pad2(clock.min);
            auxText = (clock.hour < 12) ? "AM" : "PM";
        }

        var mainH = dc.getFontHeight(font);
        var auxH = dc.getFontHeight(auxFont);
        var auxGap = Math.round(auxH * 0.15);

        var mainW = dc.getTextWidthInPixels(mainText, font);
        var auxW = dc.getTextWidthInPixels(auxText, auxFont);
        var total = mainW + auxGap + auxW;
        var x = Math.round(cx - total / 2.0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawTextV(dc, x, cy, font, mainText, Graphics.TEXT_JUSTIFY_LEFT);

        // Seconds / AM-PM sit on the baseline of the big time.
        var auxY = cy + (mainH - auxH) / 2.0 - Math.round(mainH * 0.12);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        drawTextV(dc, x + mainW + auxGap, auxY, auxFont, auxText, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // ------------------------------------------------------- sun rise / set

    private function drawSunRow(dc as Graphics.Dc, w as Numeric, cy as Numeric,
                                iconR as Numeric, gap as Numeric,
                                font as Graphics.FontType, auxFont as Graphics.FontType,
                                is24 as Boolean) as Void {
        var riseParts = fmtTimeParts(_sun.sunriseMin, is24);
        var setParts = fmtTimeParts(_sun.sunsetMin, is24);

        var riseW = timeBlockWidth(dc, iconR, gap, font, auxFont, riseParts);
        var setW = timeBlockWidth(dc, iconR, gap, font, auxFont, setParts);
        var midGap = 2 * iconR + 4;

        var left = Math.round((w - (riseW + midGap + setW)) / 2.0);

        drawTimeBlock(dc, left, cy, iconR, gap, font, auxFont, riseParts, true);
        drawTimeBlock(dc, left + riseW + midGap, cy, iconR, gap, font, auxFont, setParts, false);
    }

    private function drawSunLine(dc as Graphics.Dc, w as Numeric, cy as Numeric,
                                 iconR as Numeric, gap as Numeric,
                                 font as Graphics.FontType, auxFont as Graphics.FontType,
                                 is24 as Boolean, rise as Boolean) as Void {
        var parts = fmtTimeParts(rise ? _sun.sunriseMin : _sun.sunsetMin, is24);
        var blockW = timeBlockWidth(dc, iconR, gap, font, auxFont, parts);
        var left = Math.round((w - blockW) / 2.0);

        drawTimeBlock(dc, left, cy, iconR, gap, font, auxFont, parts, rise);
    }

    //! One "icon + HH:MM + small AM/PM" block, left-aligned at leftX.
    private function drawTimeBlock(dc as Graphics.Dc, leftX as Numeric, cy as Numeric,
                                   iconR as Numeric, gap as Numeric,
                                   font as Graphics.FontType, auxFont as Graphics.FontType,
                                   parts as Array<String>, rise as Boolean) as Void {
        var iconW = 2 * iconR + 2;
        var mainX = leftX + iconW + gap;

        drawSunIcon(dc, leftX + iconR + 1, cy, iconR, rise);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawTextV(dc, mainX, cy, font, parts[0], Graphics.TEXT_JUSTIFY_LEFT);

        if (parts[1] != "") {
            var mainH = dc.getFontHeight(font);
            var auxH = dc.getFontHeight(auxFont);
            var mainW = dc.getTextWidthInPixels(parts[0], font);
            var auxGap = Math.round(auxH * 0.15);
            var auxY = cy + (mainH - auxH) / 2.0 - Math.round(mainH * 0.12);

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            drawTextV(dc, mainX + mainW + auxGap, auxY, auxFont, parts[1],
                      Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    private function timeBlockWidth(dc as Graphics.Dc, iconR as Numeric, gap as Numeric,
                                    font as Graphics.FontType, auxFont as Graphics.FontType,
                                    parts as Array<String>) as Numeric {
        var iconW = 2 * iconR + 2;
        var width = iconW + gap + dc.getTextWidthInPixels(parts[0], font);
        if (parts[1] != "") {
            width = width + Math.round(dc.getFontHeight(auxFont) * 0.15)
                + dc.getTextWidthInPixels(parts[1], auxFont);
        }
        return width;
    }

    //! Half sun over the horizon: dome above for sunrise, below for sunset.
    private function drawSunIcon(dc as Graphics.Dc, x as Numeric, y as Numeric,
                                 r as Numeric, rise as Boolean) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        if (rise) {
            dc.fillRectangle(x - r - 1, y + 1, 2 * r + 2, r + 2);
        } else {
            dc.fillRectangle(x - r - 1, y - r - 1, 2 * r + 2, r + 1);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawLine(x - r - 2, y, x + r + 2, y);
    }

    // ------------------------------------------------------------ blue hour

    private function drawBlueHour(dc as Graphics.Dc, w as Numeric, cy as Numeric,
                                  clock as System.ClockTime, is24 as Boolean,
                                  font as Graphics.FontType) as Void {
        var nowMin = clock.hour * 60 + clock.min;
        var start = -1;
        var end = -1;
        var inside = false;

        var mS = _sun.morningBlueStart;
        var mE = _sun.morningBlueEnd;
        var eS = _sun.eveningBlueStart;
        var eE = _sun.eveningBlueEnd;

        if (mS >= 0 && nowMin >= mS && nowMin <= mE) {
            start = mS; end = mE; inside = true;
        } else if (eS >= 0 && nowMin >= eS && nowMin <= eE) {
            start = eS; end = eE; inside = true;
        } else if (mS >= 0 && nowMin < mS) {
            start = mS; end = mE;
        } else if (eS >= 0 && nowMin < eS) {
            start = eS; end = eE;
        } else if (mS >= 0) {
            // Tomorrow morning.
            start = mS; end = mE;
        } else if (eS >= 0) {
            start = eS; end = eE;
        }

        if (start < 0) {
            return;
        }

        if (inside) {
            var text = "BLUE HOUR";
            var textW = dc.getTextWidthInPixels(text, font);
            var fontH = dc.getFontHeight(font);

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Math.round(w / 2 - textW / 2.0) - 7,
                                    Math.round(cy - fontH / 2.0) - 3,
                                    textW + 14, fontH + 6, 5);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            drawTextV(dc, w / 2, cy, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var mainText = "BLUE " + fmtBlue(start, is24) + " - " + fmtBlue(end, is24);
        var suffix = meridiem(start, is24);
        var auxFont = Graphics.FONT_XTINY;

        var mainW = dc.getTextWidthInPixels(mainText, font);
        var auxW = (suffix == "") ? 0 : dc.getTextWidthInPixels(suffix, auxFont);
        var auxGap = (suffix == "") ? 0 : Math.round(dc.getFontHeight(auxFont) * 0.15);
        var total = mainW + auxGap + auxW;
        var x = Math.round(w / 2.0 - total / 2.0);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        drawTextV(dc, x, cy, font, mainText, Graphics.TEXT_JUSTIFY_LEFT);

        if (suffix != "") {
            var mainH = dc.getFontHeight(font);
            var auxH = dc.getFontHeight(auxFont);
            var auxY = cy + (mainH - auxH) / 2.0 - Math.round(mainH * 0.12);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            drawTextV(dc, x + mainW + auxGap, auxY, auxFont, suffix,
                      Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // ------------------------------------------------------------- helpers

    //! Minimal fallback if drawing fails: never leave the field blank.
    private function drawFallback(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var clock = System.getClockTime();
        var text = pad2(clock.hour) + ":" + pad2(clock.min);
        var cy = dc.getHeight() / 2;

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(dc.getWidth() / 2, cy,
                    Graphics.FONT_MEDIUM, text, Graphics.TEXT_JUSTIFY_CENTER);

        if (_lastError != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2,
                        cy + dc.getFontHeight(Graphics.FONT_MEDIUM),
                        Graphics.FONT_XTINY, _lastError as String,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawTextV(dc as Graphics.Dc, x as Numeric, cy as Numeric,
                               font as Graphics.FontType, text as String,
                               justify as Number) as Void {
        dc.drawText(Math.round(x), Math.round(cy - dc.getFontHeight(font) / 2.0),
                    font, text, justify);
    }

    private function pickTimeFont(minSide as Number) as Graphics.FontType {
        if (minSide >= 220) {
            return Graphics.FONT_NUMBER_MEDIUM;
        }
        if (minSide >= 170) {
            return Graphics.FONT_NUMBER_MILD;
        }
        if (minSide >= 140) {
            return Graphics.FONT_MEDIUM;
        }
        return Graphics.FONT_SMALL;
    }

    private function pickAuxFont(minSide as Number) as Graphics.FontType {
        return Graphics.FONT_XTINY;
    }

    private function pickSunFont(minSide as Number) as Graphics.FontType {
        if (minSide >= 200) {
            return Graphics.FONT_MEDIUM;
        }
        if (minSide >= 150) {
            return Graphics.FONT_SMALL;
        }
        return Graphics.FONT_TINY;
    }

    private function pickBlueFont(minSide as Number) as Graphics.FontType {
        if (minSide >= 220) {
            return Graphics.FONT_TINY;
        }
        return Graphics.FONT_XTINY;
    }

    private function pad2(v as Number) as String {
        return (v < 10) ? ("0" + v) : ("" + v);
    }

    //! Returns [main, suffix]: ["07:17", ""] for 24h, ["7:17", "AM"] for 12h.
    private function fmtTimeParts(minutes as Number, is24 as Boolean) as Array<String> {
        if (minutes < 0) {
            return ["--:--", ""];
        }
        var hh = (minutes / 60).toNumber();
        var mm = (minutes % 60).toNumber();
        if (is24) {
            return [pad2(hh) + ":" + pad2(mm), ""];
        }
        var h12 = hh % 12;
        if (h12 == 0) {
            h12 = 12;
        }
        return ["" + h12 + ":" + pad2(mm), (hh < 12) ? "AM" : "PM"];
    }

    //! "16:51" in 24h mode, "4:51" in 12h mode (meridiem added separately).
    private function fmtBlue(minutes as Number, is24 as Boolean) as String {
        if (minutes < 0) {
            return "--:--";
        }
        var hh = (minutes / 60).toNumber();
        var mm = (minutes % 60).toNumber();
        if (is24) {
            return pad2(hh) + ":" + pad2(mm);
        }
        var h12 = hh % 12;
        if (h12 == 0) {
            h12 = 12;
        }
        return "" + h12 + ":" + pad2(mm);
    }

    //! " AM" / " PM" for 12h mode, empty string in 24h mode.
    private function meridiem(minutes as Number, is24 as Boolean) as String {
        if (is24 || minutes < 0) {
            return "";
        }
        return ((minutes / 60).toNumber() < 12) ? " AM" : " PM";
    }
}
