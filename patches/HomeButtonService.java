package com.ivantrj.glasslauncher;

import android.accessibilityservice.AccessibilityService;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.accessibility.AccessibilityEvent;

import java.util.List;

/**
 * Fire OS protects Amazon's launcher, so it stays the system home. Whenever Amazon's
 * home comes to the front (Home press, boot, an app exiting) this brings Glass back on top.
 *
 * Fire OS 7 (Android 9) holds activity starts from background apps for 5 seconds after
 * every Home press. Moving Glass's existing task to the front with
 * ActivityManager.AppTask.moveToFront() is not held, so it is tried first;
 * startActivity() is the fallback (first launch after boot, or if the task is gone).
 *
 * The service only receives window-state events from com.amazon.tv.launcher. It does not
 * filter or see key presses, so it is never in the remote's input path.
 */
public class HomeButtonService extends AccessibilityService {

    private static final String TAG = "GlassGap";
    private static final String AMAZON_LAUNCHER = "com.amazon.tv.launcher";

    private final Handler handler = new Handler(Looper.getMainLooper());
    private long lastLaunch;

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        CharSequence pkg = event.getPackageName();
        if (event.getEventType() == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
                && pkg != null && AMAZON_LAUNCHER.contentEquals(pkg)) {
            Log.i(TAG, "amazon window event");
            openGlass();
        }
    }

    private void openGlass() {
        final long now = SystemClock.uptimeMillis();
        if (now - lastLaunch < 600) return; // one launch per Home press / launcher flash
        lastLaunch = now;

        boolean moved = bringTaskToFront();
        Log.i(TAG, "openGlass moveToFront=" + moved);
        if (!moved) {
            startGlass();
            return;
        }
        // Safety net: if Glass is not on screen shortly after, fall back to a normal start
        handler.postDelayed(new Runnable() {
            @Override
            public void run() {
                if (!GlassState.visible) {
                    Log.i(TAG, "Glass not visible after moveToFront, using startActivity");
                    startGlass();
                }
            }
        }, 1500);
    }

    /** Moves Glass's existing task to the front. Not held back by Fire OS 7's 5 second app-switch block. */
    private boolean bringTaskToFront() {
        try {
            ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            List<ActivityManager.AppTask> tasks = am.getAppTasks();
            if (tasks == null || tasks.isEmpty()) return false;
            ActivityManager.AppTask target = tasks.get(0);
            for (ActivityManager.AppTask task : tasks) {
                ActivityManager.RecentTaskInfo info = task.getTaskInfo();
                if (info != null && info.baseIntent != null && info.baseIntent.getComponent() != null
                        && HomeActivity.class.getName().equals(info.baseIntent.getComponent().getClassName())) {
                    target = task;
                    break;
                }
            }
            target.moveToFront();
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "moveToFront failed: " + t);
            return false;
        }
    }

    private void startGlass() {
        try {
            startActivity(new Intent(this, HomeActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT));
        } catch (Throwable t) {
            Log.w(TAG, "startActivity failed: " + t);
        }
    }

    @Override public void onInterrupt() {}
}
