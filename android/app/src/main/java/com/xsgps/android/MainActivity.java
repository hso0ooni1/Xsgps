package com.xsgps.android;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.location.Address;
import android.location.Geocoder;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.text.InputType;
import android.view.*;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.*;
import org.json.*;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.Executors;
import java.util.regex.*;

public final class MainActivity extends Activity {
    private static final int BG=Color.rgb(7,19,29), CARD=Color.rgb(16,36,49),
      GREEN=Color.rgb(64,206,179), WHITE=Color.rgb(244,252,252), MUTED=Color.rgb(162,187,196);
    private LinearLayout root, savedList;
    private EditText latitude,longitude,lookup,code;
    private TextView state,licenseState,radiusLabel;
    private SeekBar radiusSeek;
    private CheckBox randomMovement;
    private final java.util.concurrent.ExecutorService bg=Executors.newSingleThreadExecutor();
    @Override public void onCreate(Bundle b){
        super.onCreate(b);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        build();
        updateStatus();
        LicenseClient.installId(this);
        if(LicenseClient.prefs(this).getBoolean("license_active",false))
            LicenseClient.verify(this,(ok,msg)->{licenseState.setText("التفعيل: "+msg);});
    }
    private GradientDrawable shape(int fill,int stroke,int radius){
        GradientDrawable d=new GradientDrawable();
        d.setColor(fill);d.setCornerRadius(dp(radius));if(stroke!=0)d.setStroke(dp(1),stroke);return d;
    }
    private int dp(int n){return (int)(n*getResources().getDisplayMetrics().density+0.5f);}
    private LinearLayout vertical(){LinearLayout l=new LinearLayout(this);l.setOrientation(LinearLayout.VERTICAL);return l;}
    private TextView label(String text,int size,int color,boolean bold){
        TextView t=new TextView(this);t.setText(text);t.setTextSize(size);t.setTextColor(color);
        t.setGravity(Gravity.RIGHT);t.setTextDirection(View.TEXT_DIRECTION_RTL);
        if(bold)t.setTypeface(null,Typeface.BOLD);return t;
    }
    private void pad(View v,int h,int top,int bottom){v.setPadding(dp(h),dp(top),dp(h),dp(bottom));}
    private LinearLayout section(String title){
        LinearLayout s=vertical();s.setBackground(shape(CARD,Color.rgb(30,67,78),20));
        pad(s,16,17,15);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,-2);
        lp.setMargins(0,0,0,dp(13));root.addView(s,lp);
        TextView t=label(title,19,WHITE,true);
        LinearLayout.LayoutParams tlp=new LinearLayout.LayoutParams(-1,-2);tlp.bottomMargin=dp(13);
        s.addView(t,tlp);return s;
    }
    private EditText field(String hint,String initial,boolean numeric){
        EditText e=new EditText(this);e.setSingleLine(true);e.setTextColor(WHITE);
        e.setHintTextColor(MUTED);e.setTextSize(16);e.setHint(hint);
        e.setText(initial);e.setSelectAllOnFocus(true);
        e.setTextDirection(View.TEXT_DIRECTION_LTR);e.setGravity(Gravity.CENTER_VERTICAL|Gravity.LEFT);
        if(numeric)e.setInputType(InputType.TYPE_CLASS_NUMBER|InputType.TYPE_NUMBER_FLAG_DECIMAL|InputType.TYPE_NUMBER_FLAG_SIGNED);
        e.setBackground(shape(Color.rgb(10,26,39),Color.rgb(41,72,83),12));
        pad(e,12,11,11);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(49));
        p.bottomMargin=dp(9);e.setLayoutParams(p);return e;
    }
    private Button btn(String text,boolean primary,Runnable action){
        Button b=new Button(this);b.setText(text);b.setAllCaps(false);b.setTextSize(15);
        b.setTextColor(primary?BG:WHITE);
        b.setBackground(shape(primary?GREEN:Color.rgb(30,59,75),0,13));
        b.setOnClickListener(v->action.run());return b;
    }
    private void addButton(LinearLayout parent,String title,boolean primary,Runnable run){
        Button b=btn(title,primary,run);LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(49));
        p.bottomMargin=dp(9);parent.addView(b,p);
    }
    private void toast(String text){Toast.makeText(this,text,Toast.LENGTH_LONG).show();}
    private void build(){
        root=vertical();root.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);root.setBackgroundColor(BG);
        pad(root,16,24,30);
        ScrollView sc=new ScrollView(this);sc.setFillViewport(true);sc.addView(root);
        setContentView(sc);
        TextView brand=label("XsGPS  •  ANDROID",28,GREEN,true);
        root.addView(brand);TextView subtitle=label("نسخة اختبار بدون روت — موقع تجريبي رسمي",13,MUTED,false);
        LinearLayout.LayoutParams sublp=new LinearLayout.LayoutParams(-1,-2);
        sublp.bottomMargin=dp(20);root.addView(subtitle,sublp);
        state=label("",14,WHITE,false);
        LinearLayout status=section("حالة الخدمة");status.addView(state);
        addButton(status,"فتح خيارات المطوّر وتحديد تطبيق الموقع التجريبي",false,()->{
            try{startActivity(new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS));}
            catch(Exception ex){toast("افتح الإعدادات ← خيارات المطوّر ← اختيار تطبيق موقع تجريبي");}
        });
        LinearLayout position=section("اختيار الموقع");
        lookup=field("اسم مكان، إحداثيات أو رابط خرائط","",false);position.addView(lookup);
        addButton(position,"بحث عن المكان أو قراءة الإحداثيات",false,this::search);
        latitude=field("خط العرض Latitude",
                LicenseClient.prefs(this).getString("lat","24.7136"),true);
        longitude=field("خط الطول Longitude",
                LicenseClient.prefs(this).getString("lon","46.6753"),true);
        position.addView(latitude);position.addView(longitude);
        addButton(position,"فتح الخريطة واختيار نقطة",false,this::openMap);
        TextView notice=label("الخرائط تحتاج إنترنت. اضغط النقطة المطلوبة، ثم «استخدام الموقع».",12,MUTED,false);
        position.addView(notice);
        LinearLayout motion=section("الحركة العشوائية");
        randomMovement=new CheckBox(this);randomMovement.setText("تفعيل الحركة العشوائية البطيئة");
        randomMovement.setTextColor(WHITE);
        randomMovement.setChecked(LicenseClient.prefs(this).getBoolean("movement",false));
        motion.addView(randomMovement);
        radiusLabel=label("نطاق الحركة: 20 مترًا",15,MUTED,false);
        motion.addView(radiusLabel);
        radiusSeek=new SeekBar(this);radiusSeek.setMax(100);
        radiusSeek.setProgress(LicenseClient.prefs(this).getInt("radius",20));
        radiusLabel.setText("نطاق الحركة: "+radiusSeek.getProgress()+" مترًا");
        radiusSeek.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            @Override public void onProgressChanged(SeekBar b,int p,boolean u){radiusLabel.setText("نطاق الحركة: "+p+" مترًا");}
            @Override public void onStartTrackingTouch(SeekBar b){}
            @Override public void onStopTrackingTouch(SeekBar b){}
        });motion.addView(radiusSeek);
        LinearLayout actions=section("التحكم في الموقع");
        addButton(actions,"تشغيل الموقع التجريبي",true,this::startMock);
        addButton(actions,"إيقاف وإرجاع GPS الطبيعي",false,this::stopMock);
        addButton(actions,"تحديث الحالة",false,this::updateStatus);
        LinearLayout bookmarks=section("المواقع المحفوظة");
        EditText name=field("اسم الموقع للحفظ","",false);bookmarks.addView(name);
        addButton(bookmarks,"حفظ الإحداثيات الحالية",false,()->{
            try{
                double[] point=point();
                JSONArray arr=saved();
                JSONObject item=new JSONObject();
                item.put("name",name.getText().toString().trim().isEmpty()?"موقع "+(arr.length()+1):name.getText().toString().trim());
                item.put("lat",point[0]);item.put("lon",point[1]);
                if(arr.length()>=50){toast("الحد الأقصى 50 موقعًا");return;}
                arr.put(item);
                LicenseClient.prefs(this).edit().putString("bookmarks",arr.toString()).apply();
                name.setText("");refreshSaved();toast("تم حفظ الموقع");
            }catch(Exception e){toast("أدخل إحداثيات صحيحة");}
        });
        savedList=vertical();bookmarks.addView(savedList);refreshSaved();
        LinearLayout activation=section("أكواد تفعيل الأندرويد");
        licenseState=label(BuildConfig.DEBUG?
            "نسخة تجريبية: الاستخدام متاح للاختبار بدون كود. التفعيل النهائي يتطلب نشر تحديث السيرفر.":
            "أدخل كود Android من لوحة أكواد XsGpS.",13,MUTED,false);
        activation.addView(licenseState);
        code=field("كود Android (10 خانات)",
                LicenseClient.prefs(this).getString("license_code",""),false);
        activation.addView(code);
        addButton(activation,"تفعيل كود Android",true,()->{
            String value=code.getText().toString().trim();
            if(!value.matches("[A-Za-z0-9]{10}")){toast("أدخل كود التفعيل المكوّن من 10 خانات");return;}
            licenseState.setText("جاري التحقق من الكود...");
            LicenseClient.activate(this,value,(ok,msg)->{
                licenseState.setText("التفعيل: "+msg);
                toast(msg);
            });
        });
        TextView footer=label("الموقع التجريبي يظهر للتطبيقات كـ Mock Location. لا يُخفي ذلك عن التطبيقات الأخرى، ولا يعدّل ملفات APK.",12,MUTED,false);
        root.addView(footer);
    }
    private double[] point(){
        double lat=Double.parseDouble(latitude.getText().toString().trim().replace(',','.'));
        double lon=Double.parseDouble(longitude.getText().toString().trim().replace(',','.'));
        if(!Double.isFinite(lat)||!Double.isFinite(lon)||Math.abs(lat)>90||Math.abs(lon)>180)
            throw new IllegalArgumentException("Invalid coords");
        return new double[]{lat,lon};
    }
    private void savePosition(double lat,double lon){
        latitude.setText(String.format(Locale.US,"%.7f",lat));
        longitude.setText(String.format(Locale.US,"%.7f",lon));
        LicenseClient.prefs(this).edit().putString("lat",latitude.getText().toString())
                .putString("lon",longitude.getText().toString()).apply();
    }
    private JSONArray saved(){
        try{return new JSONArray(LicenseClient.prefs(this).getString("bookmarks","[]"));}
        catch(Exception e){return new JSONArray();}
    }
    private void refreshSaved(){
        if(savedList==null)return;
        savedList.removeAllViews();JSONArray arr=saved();
        if(arr.length()==0){savedList.addView(label("ما عندك مواقع محفوظة بعد",13,MUTED,false));return;}
        for(int i=0;i<arr.length();i++){
            JSONObject item=arr.optJSONObject(i);if(item==null)continue;
            final int idx=i;
            String title=item.optString("name","موقع")+"    "+String.format(Locale.US,"%.5f, %.5f",item.optDouble("lat"),item.optDouble("lon"));
            Button b=btn(title,false,()->savePosition(item.optDouble("lat"),item.optDouble("lon")));
            b.setOnLongClickListener(v->{
                new AlertDialog.Builder(this).setTitle("حذف الموقع؟").setMessage(title)
                    .setPositiveButton("حذف",(d,w)->{
                        JSONArray source=saved(),next=new JSONArray();
                        for(int a=0;a<source.length();a++)if(a!=idx)next.put(source.opt(a));
                        LicenseClient.prefs(this).edit().putString("bookmarks",next.toString()).apply();
                        refreshSaved();
                    }).setNegativeButton("إلغاء",null).show();return true;
            });
            LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,dp(50));
            p.bottomMargin=dp(7);savedList.addView(b,p);
        }
        savedList.addView(label("اضغط لاختيار الموقع، أو ضغطة طويلة لحذفه.",12,MUTED,false));
    }
    private void search(){
        String q=lookup.getText().toString().trim();
        if(q.isEmpty()){toast("أدخل اسم موقع أو إحداثيات");return;}
        try{
            String decoded=URLDecoder.decode(q,StandardCharsets.UTF_8.name());
            Pattern pat=Pattern.compile("(-?\\d{1,3}(?:\\.\\d+)?)\\s*[,،]\\s*(-?\\d{1,3}(?:\\.\\d+)?)");
            Matcher m=pat.matcher(decoded);
            if(m.find()){
                double lat=Double.parseDouble(m.group(1)),lon=Double.parseDouble(m.group(2));
                if(Math.abs(lat)<=90&&Math.abs(lon)<=180){savePosition(lat,lon);toast("تم تحديد الموقع");return;}
            }
            if(q.startsWith("http")){toast("روابط الخرائط المختصرة تحتاج فتح الرابط ثم نسخ الإحداثيات.");return;}
            toast("جاري البحث عن "+q+"...");
            bg.execute(()->{
                try{
                    List<Address> results=new Geocoder(this,Locale.getDefault()).getFromLocationName(q,1);
                    runOnUiThread(()->{
                        if(results==null||results.isEmpty()){toast("لم يُعثر على الموقع. أدخل الإحداثيات.");return;}
                        Address address=results.get(0);
                        savePosition(address.getLatitude(),address.getLongitude());
                        toast("تم تحديد "+q);
                    });
                }catch(Exception ex){runOnUiThread(()->toast("البحث بالاسم غير متوفر على هذا الجهاز، جرّب الإحداثيات."));}
            });
        }catch(Exception ex){toast("تعذر قراءة الموقع");}
    }
    private void openMap(){
        try{
            double[] p=point();
            WebView web=new WebView(this);
            web.getSettings().setJavaScriptEnabled(true);
            web.getSettings().setDomStorageEnabled(false);
            web.getSettings().setAllowFileAccess(true);
            final double[] chosen={p[0],p[1]};
            LinearLayout view=vertical();
            view.addView(web,new LinearLayout.LayoutParams(-1,0,1));
            Button choose=btn("استخدام الموقع المحدد",true,()->{savePosition(chosen[0],chosen[1]);web.destroy();});
            view.addView(choose,new LinearLayout.LayoutParams(-1,dp(52)));
            AlertDialog dialog=new AlertDialog.Builder(this).setTitle("حدد الموقع على الخريطة")
                    .setView(view).setNegativeButton("إغلاق",(d,w)->web.destroy()).create();
            choose.setOnClickListener(v->{savePosition(chosen[0],chosen[1]);dialog.dismiss();web.destroy();});
            web.setWebViewClient(new WebViewClient(){
                @Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest request){
                    android.net.Uri u=request.getUrl();
                    if(!"xsgps".equalsIgnoreCase(u.getScheme()))return false;
                    if("pick".equals(u.getHost())) {
                        try{
                            double a=Double.parseDouble(u.getQueryParameter("lat"));
                            double b=Double.parseDouble(u.getQueryParameter("lon"));
                            if(Math.abs(a)<=90&&Math.abs(b)<=180){chosen[0]=a;chosen[1]=b;}
                        }catch(Exception ignored){}
                    }
                    return true;
                }
            });
            web.loadUrl(String.format(Locale.US,"file:///android_asset/map.html?lat=%.7f&lon=%.7f",p[0],p[1]));
            dialog.show();
            dialog.getWindow().setLayout(-1,(int)(getResources().getDisplayMetrics().heightPixels*0.82));
        }catch(Exception e){toast("أدخل إحداثيات صحيحة أولًا");}
    }
    private void startMock(){
        if(!BuildConfig.DEBUG && !LicenseClient.recentlyVerified(this)){
            toast("فعّل كود Android وتأكد من اتصال السيرفر أولًا");return;
        }
        double[] p;
        try{p=point();}catch(Exception e){toast("تأكد من خط العرض والطول");return;}
        if(checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)!=PackageManager.PERMISSION_GRANTED){
            requestPermissions(new String[]{Manifest.permission.ACCESS_FINE_LOCATION,
                  Manifest.permission.ACCESS_COARSE_LOCATION},101);return;
        }
        LicenseClient.prefs(this).edit().putString("lat",latitude.getText().toString())
            .putString("lon",longitude.getText().toString()).putBoolean("movement",randomMovement.isChecked())
            .putInt("radius",radiusSeek.getProgress()).putString("mock_error","").apply();
        Intent s=new Intent(this,MockLocationService.class).setAction(MockLocationService.START)
            .putExtra("lat",p[0]).putExtra("lon",p[1])
            .putExtra("movement",randomMovement.isChecked())
            .putExtra("radius",(double)radiusSeek.getProgress());
        try{startForegroundService(s);toast("جاري تشغيل الموقع التجريبي");state.postDelayed(this::updateStatus,900);}
        catch(Exception e){toast("فشل تشغيل الخدمة. امنح إذن الموقع واختر التطبيق للموقع التجريبي.");}
    }
    private void stopMock(){
        startService(new Intent(this,MockLocationService.class).setAction(MockLocationService.STOP));
        state.postDelayed(this::updateStatus,450);
        toast("تم إرسال أمر الإيقاف");
    }
    private void updateStatus(){
        android.content.SharedPreferences p=LicenseClient.prefs(this);
        String error=p.getString("mock_error","");
        state.setText(error.length()>0?error:
             p.getBoolean("mock_active",false)?"الموقع التجريبي يعمل الآن":"الموقع التجريبي متوقف");
        state.setTextColor(error.length()>0?Color.rgb(255,169,120):p.getBoolean("mock_active",false)?GREEN:MUTED);
    }
    @Override public void onRequestPermissionsResult(int req,String[] perm,int[] results){
        super.onRequestPermissionsResult(req,perm,results);
        if(req==101){
            if(results.length>0&&results[0]==PackageManager.PERMISSION_GRANTED)startMock();
            else toast("الموقع الدقيق مطلوب لتشغيل الموقع التجريبي");
        }
    }
    @Override protected void onResume(){super.onResume();if(state!=null)updateStatus();}
    @Override protected void onDestroy(){bg.shutdownNow();super.onDestroy();}
}
