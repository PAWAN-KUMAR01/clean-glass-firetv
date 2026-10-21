package com.ivantrj.glasslauncher;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;

import java.util.ArrayList;
import java.util.List;

/**
 * Fire OS 7 draws its main Settings grid inside Amazon's home screen, which the Home
 * redirect would bounce straight back from. Each settings page is its own screen in
 * com.amazon.tv.settings.v2, so Glass lists those and opens them directly; Home from
 * any of them returns to Glass through the normal redirect.
 */
final class SettingsMenu {

    private static final String PKG = "com.amazon.tv.settings.v2";
    private static final String[][] PAGES = {
            {"Network", ".tv.network.NetworkActivity"},
            {"Display & Sounds", ".tv.display_sounds.DisplayAndSoundsActivity"},
            {"Remotes & Bluetooth", ".tv.controllers_bluetooth_devices.ControllersAndBluetoothActivity"},
            {"Applications", ".tv.applications.ApplicationsActivity"},
            {"My Fire TV", ".tv.device.DeviceActivity"},
            {"Preferences", ".tv.preferences.PreferencesActivity"},
            {"Accessibility", ".tv.accessibility.AccessibilityActivity"},
            {"Account & Profiles", ".tv.my_account.MyAccountActivity"},
    };

    static List<InputsMenu.Entry> load(Context context) {
        PackageManager pm = context.getPackageManager();
        List<InputsMenu.Entry> out = new ArrayList<>();
        for (String[] page : PAGES) {
            ComponentName cn = new ComponentName(PKG, PKG + page[1]);
            try {
                ActivityInfo info = pm.getActivityInfo(cn, 0);
                if (info == null || !info.exported) continue;
            } catch (PackageManager.NameNotFoundException e) {
                continue;
            }
            out.add(new InputsMenu.Entry(page[0], new Intent().setComponent(cn).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        }
        if (out.isEmpty()) out.add(new InputsMenu.Entry("Settings not available", null));
        return out;
    }

    private SettingsMenu() {}
}
