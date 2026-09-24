package com.xsgps.embed;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;
import org.json.JSONObject;
import java.net.HttpURLConnection;
import java.net.URL;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class XsGpsLicense {
    static final String SERVER = "https://location-spoofer-api.hso0ooni14.workers.dev";
    private static final ExecutorService NETWORK = Executors.newSingleThreadExecutor();
    interface Result { void onResult(boolean ok, String message); }
    static SharedPreferences prefs(Context c) {
        return c.getSharedPreferences("xsgps_android", Context.MODE_PRIVATE);
    }
    static String installId(Context c) {
        SharedPreferences p=prefs(c);
        String uuid=p.getString("install_uuid", "");
        if(uuid.length()==0) {
            uuid=UUID.randomUUID().toString().toUpperCase();
            p.edit().putString("install_uuid", uuid).apply();
        }
        return uuid;
    }
    static boolean recentlyVerified(Context c) {
        SharedPreferences p=prefs(c);
        return p.getBoolean("license_active",false)
                && System.currentTimeMillis()-p.getLong("verified_at",0) < 24*60*60*1000L;
    }
    static void activate(Context c, String code, Result result) {
        send(c, "/activate", code, result);
    }
    static void verify(Context c, Result result) {
        send(c, "/verify", prefs(c).getString("license_code",""), result);
    }
    private static void send(Context ctx, String path, String code, Result callback) {
        final Context c=ctx.getApplicationContext();
        NETWORK.execute(()->{
            HttpURLConnection conn=null;
            boolean ok=false; String message="تعذر الوصول إلى سيرفر الأكواد";
            try {
                JSONObject body=new JSONObject();
                String id=Settings.Secure.getString(c.getContentResolver(),Settings.Secure.ANDROID_ID);
                if(id==null || id.length()==0) id=installId(c);
                body.put("code",code.trim().toUpperCase());
                body.put("platform","android");
                body.put("device_id",id);
                body.put("app_uuid",installId(c));
                body.put("device_name",Build.MANUFACTURER+" "+Build.MODEL);
                body.put("device_udid",id);
                body.put("ios_version",Build.VERSION.RELEASE);
                body.put("system_name","Android");
                body.put("device_model",Build.MODEL);
                body.put("app_version","0.1-beta");
                conn=(HttpURLConnection)new URL(SERVER+path).openConnection();
                conn.setRequestMethod("POST");
                conn.setConnectTimeout(12000);
                conn.setReadTimeout(12000);
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type","application/json; charset=utf-8");
                byte[] payload=body.toString().getBytes(StandardCharsets.UTF_8);
                try(OutputStream out=conn.getOutputStream()){out.write(payload);}
                InputStream input=conn.getResponseCode()<400?conn.getInputStream():conn.getErrorStream();
                String response="";
                if(input!=null) {
                    try(InputStream stream=input; ByteArrayOutputStream buffer=new ByteArrayOutputStream()) {
                        byte[] bytes=new byte[4096];int n;
                        while((n=stream.read(bytes))!=-1)buffer.write(bytes,0,n);
                        response=new String(buffer.toByteArray(),StandardCharsets.UTF_8);
                    }
                }
                JSONObject json=new JSONObject(response);
                ok=conn.getResponseCode()==200 && json.optBoolean("ok",false);
                message=json.optString("message",ok?"تم التفعيل":"تعذر التفعيل");
                if(ok) {
                    prefs(c).edit().putString("license_code",code.trim().toUpperCase())
                          .putBoolean("license_active",true)
                          .putLong("verified_at",System.currentTimeMillis()).apply();
                } else if(path.equals("/verify")) {
                    prefs(c).edit().putBoolean("license_active",false).apply();
                }
            } catch(Exception ex) {
                message="تعذر الاتصال بسيرفر الأكواد. تأكد من نشر تحديث Android على Cloudflare.";
            } finally {if(conn!=null) conn.disconnect();}
            final boolean success=ok;final String msg=message;
            android.os.Handler main=new android.os.Handler(android.os.Looper.getMainLooper());
            main.post(()->callback.onResult(success,msg));
        });
    }
}
