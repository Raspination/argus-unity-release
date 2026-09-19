package com.argus;

import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.content.Context;
import android.os.Build;

import com.unity3d.player.UnityPlayer;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.InputStream;
import java.util.List;

/**
 * Ground-truth ANR reader for Argus. Reads the OS-recorded exit-reason history
 * (ActivityManager.getHistoricalProcessExitReasons, API 30+), keeps only
 * REASON_ANR entries, and returns them as JSON for the C# NativeAnrBridge to
 * fold into the next session.
 *
 * This walks data the OS already persisted — it installs no signal handler, so
 * it never contends with Crashlytics' SIGQUIT handler. Best-effort: any failure
 * returns an empty {"items":[]} rather than throwing into the JNI caller.
 *
 * Ships as source under Assets/Argus/Plugins/Android/; Unity's Gradle build
 * compiles it into the player. The C# bridge stays in Argus.Runtime.dll.
 */
public final class AnrBridge {

    // Cap the trace excerpt so a multi-MB ANR dump can't bloat the capture
    // payload — the first frames are where the deadlock/contention shows.
    private static final int MAX_TRACE_CHARS = 16 * 1024;

    private AnrBridge() {}

    public static String collectAnrsJson() {
        JSONObject root = new JSONObject();
        JSONArray items = new JSONArray();
        try {
            root.put("items", items);

            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                // getHistoricalProcessExitReasons is API 30+; older devices fall
                // back to the always-on C# watchdog only.
                return root.toString();
            }

            Context ctx = UnityPlayer.currentActivity;
            if (ctx == null) return root.toString();
            ctx = ctx.getApplicationContext();

            ActivityManager am =
                    (ActivityManager) ctx.getSystemService(Context.ACTIVITY_SERVICE);
            if (am == null) return root.toString();

            // 0/0 = current package, all pids, no cap → the full rolling history
            // the OS retains (typically the last ~16 exits).
            List<ApplicationExitInfo> history =
                    am.getHistoricalProcessExitReasons(ctx.getPackageName(), 0, 0);
            if (history == null) return root.toString();

            for (ApplicationExitInfo info : history) {
                if (info.getReason() != ApplicationExitInfo.REASON_ANR) continue;

                JSONObject item = new JSONObject();
                // Timestamp is ms-since-epoch; the C# side stores unix seconds.
                item.put("atUnixTime", info.getTimestamp() / 1000.0);
                item.put("stallMs", 0f); // the OS doesn't expose the stall length
                item.put("source", "android_exit_info");
                item.put("traceExcerpt", readTrace(info));
                items.put(item);
            }
        } catch (Throwable t) {
            // Swallow — a broken read must never crash the game it's profiling.
        }
        return root.toString();
    }

    private static String readTrace(ApplicationExitInfo info) {
        try (InputStream in = info.getTraceInputStream()) {
            if (in == null) return null;
            byte[] buf = new byte[MAX_TRACE_CHARS];
            int total = 0, n;
            while (total < buf.length && (n = in.read(buf, total, buf.length - total)) > 0) {
                total += n;
            }
            if (total <= 0) return null;
            return new String(buf, 0, total);
        } catch (Throwable t) {
            return null;
        }
    }
}
