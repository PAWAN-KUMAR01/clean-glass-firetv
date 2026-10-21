package com.ivantrj.glasslauncher;

import android.content.Context;
import android.util.Log;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.List;

/**
 * The order you arrange with Menu > Move: dock.txt holds the dock (left to right),
 * grid.txt the grid. Apps not in grid.txt (newly installed) keep alphabetical order at the end.
 */
final class GlassOrder {
    private GlassOrder() {}

    static void apply(Context context, List<AppInfo> grid) {
        final List<String> order = AppLoader.readList(context, "grid.txt");
        if (order.isEmpty()) return;
        // List.sort is stable, so unlisted apps stay alphabetical among themselves
        grid.sort((a, b) -> Integer.compare(rank(order, a.packageName), rank(order, b.packageName)));
    }

    private static int rank(List<String> order, String pkg) {
        int i = order.indexOf(pkg);
        return i < 0 ? Integer.MAX_VALUE : i;
    }

    static void save(Context context, List<AppInfo> dock, List<AppInfo> grid) {
        write(context, "dock.txt", dock);
        write(context, "grid.txt", grid);
    }

    private static void write(Context context, String fileName, List<AppInfo> apps) {
        try (FileWriter w = new FileWriter(new File(context.getFilesDir(), fileName))) {
            for (AppInfo app : apps) w.write(app.packageName + "\n");
        } catch (IOException e) {
            Log.w("GlassOrder", "could not save " + fileName + ": " + e);
        }
    }
}
