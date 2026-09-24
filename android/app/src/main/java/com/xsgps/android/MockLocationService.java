package com.xsgps.android;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.location.Criteria;
import android.location.Location;
import android.location.LocationManager;
import android.os.*;
import java.util.Random;

public final class MockLocationService extends Service {
    static final String START="com.xsgps.android.START";
    static final String STOP="com.xsgps.android.STOP";
    private static final String CHANNEL="xsgps_test_location";
    private LocationManager manager;
    private Handler handler;
    private boolean added=false;
    private boolean running=false;
    private final Random random=new Random();
    private double anchorLat,anchorLon,lat,lon;
    private boolean movement;
    private double radius;
    private final Runnable tick=new Runnable(){
        @Override public void run(){
            if(!running)return;
            if(movement && radius>0.0){
                double north=(random.nextDouble()*2-1)*2.0;
                double east=(random.nextDouble()*2-1)*2.0;
                double proposedLat=lat+north/111320.0;
                double proposedLon=lon+east/(111320.0*Math.max(0.01,Math.cos(Math.toRadians(lat))));
                double dy=(proposedLat-anchorLat)*111320.0;
                double dx=(proposedLon-anchorLon)*111320.0*Math.cos(Math.toRadians(anchorLat));
                if(Math.hypot(dx,dy)<radius){lat=proposedLat;lon=proposedLon;}
            }
            try {
                Location fake=new Location(LocationManager.GPS_PROVIDER);
                fake.setLatitude(lat);
                fake.setLongitude(lon);
                fake.setAccuracy(3.0f);
                fake.setAltitude(0);
                fake.setTime(System.currentTimeMillis());
                fake.setElapsedRealtimeNanos(SystemClock.elapsedRealtimeNanos());
                if(movement) fake.setSpeed(0.7f);
                manager.setTestProviderLocation(LocationManager.GPS_PROVIDER,fake);
                getSharedPreferences("xsgps_android",MODE_PRIVATE).edit()
                    .putBoolean("mock_active",true).putString("mock_error","").apply();
                handler.postDelayed(this,2500);
            }catch(Exception ex){report("فشل المحاكاة: اختر XsGPS من خيارات المطور كتطبيق موقع تجريبي.");stopSelf();}
        }
    };
    @Override public void onCreate(){
        super.onCreate();
        manager=(LocationManager)getSystemService(LOCATION_SERVICE);
        handler=new Handler(Looper.getMainLooper());
        NotificationManager nm=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL,"XsGPS: موقع تجريبي",NotificationManager.IMPORTANCE_LOW));
    }
    private Notification notification(){
        Intent i=new Intent(this,MainActivity.class);
        PendingIntent pi=PendingIntent.getActivity(this,0,i,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
        return new Notification.Builder(this,CHANNEL).setSmallIcon(android.R.drawable.ic_menu_mylocation)
           .setContentTitle("XsGPS Android").setContentText("محاكاة موقع اختبارية نشطة")
           .setContentIntent(pi).setOngoing(true).build();
    }
    @Override public int onStartCommand(Intent intent,int flags,int startId){
        if(intent==null)return START_NOT_STICKY;
        if(STOP.equals(intent.getAction())){stopSelf();return START_NOT_STICKY;}
        if(!START.equals(intent.getAction()))return START_NOT_STICKY;
        if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){
            report("امنح التطبيق إذن الموقع الدقيق أولاً");stopSelf();return START_NOT_STICKY;
        }
        try {startForeground(19,notification());}
        catch(Exception e){report("تعذر تشغيل خدمة الموقع: "+e.getClass().getSimpleName());stopSelf();return START_NOT_STICKY;}
        handler.removeCallbacks(tick);
        anchorLat=intent.getDoubleExtra("lat",0);
        anchorLon=intent.getDoubleExtra("lon",0);
        lat=anchorLat;lon=anchorLon;
        movement=intent.getBooleanExtra("movement",false);
        radius=Math.max(0,Math.min(100,intent.getDoubleExtra("radius",20)));
        if(!Double.isFinite(lat)||!Double.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180){
            report("إحداثيات غير صالحة");stopSelf();return START_NOT_STICKY;
        }
        try {
            if(added) {manager.removeTestProvider(LocationManager.GPS_PROVIDER);added=false;}
            // Requires manual selection as the mock location app in Developer Options.
            manager.addTestProvider(LocationManager.GPS_PROVIDER,false,false,false,false,
                    true,true,true,Criteria.POWER_LOW,Criteria.ACCURACY_FINE);
            added=true;
            manager.setTestProviderEnabled(LocationManager.GPS_PROVIDER,true);
            running=true;
            handler.post(tick);
        }catch(Exception e){report("اختر XsGPS في «تطبيق الموقع الوهمي» بخيارات المطور أولًا.");stopSelf();}
        return START_NOT_STICKY;
    }
    private void report(String error){
        getSharedPreferences("xsgps_android",MODE_PRIVATE).edit()
            .putBoolean("mock_active",false).putString("mock_error",error).apply();
    }
    @Override public void onDestroy(){
        running=false;handler.removeCallbacks(tick);
        if(added)try{manager.removeTestProvider(LocationManager.GPS_PROVIDER);}catch(Exception ignored){}
        added=false;
        getSharedPreferences("xsgps_android",MODE_PRIVATE).edit().putBoolean("mock_active",false).apply();
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent i){return null;}
}
