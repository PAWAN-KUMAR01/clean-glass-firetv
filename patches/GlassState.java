package com.ivantrj.glasslauncher;

import android.os.SystemClock;
import android.util.Log;

/** Lets the Home redirect know whether Glass is on screen. Updated from HomeActivity.onStart/onStop. */
final class GlassState {
    static volatile boolean visible;
    static volatile long changedAt;

    private GlassState() {}

    static void set(boolean isVisible) {
        visible = isVisible;
        changedAt = SystemClock.uptimeMillis();
        Log.i("GlassGap", "glass visible=" + isVisible);
    }
}
