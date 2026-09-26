package com.xsgps.module;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.view.Gravity;
import android.widget.FrameLayout;
import android.widget.TextView;
import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/** Visible test shortcut restricted to the XsGPS-owned sample application. */
public final class ModuleEntry implements IXposedHookLoadPackage {
    private static final String SAMPLE = "com.xsgps.android";
    private static final String MODULE = "com.xsgps.module";
    @Override public void handleLoadPackage(XC_LoadPackage.LoadPackageParam p) {
        if (!SAMPLE.equals(p.packageName)) return;
        XposedBridge.hookAllMethods(Activity.class, "onResume", new XC_MethodHook() {
            @Override protected void afterHookedMethod(MethodHookParam result) {
                Activity activity = (Activity) result.thisObject;
                if (!SAMPLE.equals(activity.getPackageName())) return;
                activity.runOnUiThread(() -> addShortcut(activity));
            }
        });
    }
    private static void addShortcut(Activity host) {
        FrameLayout root = host.findViewById(android.R.id.content);
        if (root == null || root.findViewWithTag("xsgps-test-module") != null) return;
        TextView button = new TextView(host);
        button.setTag("xsgps-test-module");
        button.setText("XS GPS");
        button.setTextColor(Color.WHITE);
        button.setBackgroundColor(Color.rgb(12, 105, 108));
        button.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(160, 100, Gravity.END | Gravity.CENTER_VERTICAL);
        root.addView(button, lp);
        button.setOnClickListener(v -> {
            Intent launch = new Intent();
            launch.setClassName(MODULE, MODULE + ".MainActivity");
            try { host.startActivity(launch); }
            catch (Exception e) { XposedBridge.log("XsGPS test module: install module APK first"); }
        });
    }
}
