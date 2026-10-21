package com.ivantrj.glasslauncher;

import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;

/**
 * Lets the dock and hidden-app lists be changed with an intent, so they work in a
 * non-debuggable (faster) build where configure.sh's run-as trick is not allowed:
 *   am start -n com.ivantrj.glasslauncher/.HomeActivity --esa dock pkg1,pkg2 --ez reload true
 *   am start -n com.ivantrj.glasslauncher/.HomeActivity --esa dock reset --ez reload true
 */
final class GlassConfig {
    private GlassConfig() {}

    static void apply(Context context, Intent intent) {
        write(context, "dock.txt", intent.getStringArrayExtra("dock"));
        write(context, "hidden.txt", intent.getStringArrayExtra("hidden"));
    }

    private static void write(Context context, String fileName, String[] packages) {
        if (packages == null) return;
        File file = new File(context.getFilesDir(), fileName);
        if (packages.length == 0 || (packages.length == 1 && "reset".equals(packages[0]))) {
            if (file.exists() && !file.delete()) Log.w("GlassConfig", "could not delete " + fileName);
            return;
        }
        try (FileWriter w = new FileWriter(file)) {
            for (String pkg : packages) {
                String p = pkg.trim();
                if (!p.isEmpty()) w.write(p + "\n");
            }
        } catch (IOException e) {
            Log.w("GlassConfig", "could not write " + fileName + ": " + e);
        }
    }
}
