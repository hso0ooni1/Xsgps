package com.xsgps.embed;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.TextView;
import java.util.WeakHashMap;

/** An in-app floating button for apps with source-code integration. */
public final class XsGpsOverlay {
    private static final WeakHashMap<Activity,View> bubbles=new WeakHashMap<>();
    private static boolean registered=false;
    private static boolean requireActivation=false;
    private XsGpsOverlay(){}
    /** Set true only once the Android Cloudflare licensing backend is deployed. */
    public static void requireActivation(boolean value){requireActivation=value;}
    static boolean activationRequired(){return requireActivation;}
    /** Attach automatically to every screen in an app you own or are allowed to modify. */
    public static synchronized void install(Application app){
        if(registered)return;
        registered=true;
        app.registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks(){
            public void onActivityCreated(Activity a,Bundle b){}
            public void onActivityStarted(Activity a){}
            public void onActivityResumed(Activity a){attach(a);}
            public void onActivityPaused(Activity a){}
            public void onActivityStopped(Activity a){}
            public void onActivitySaveInstanceState(Activity a,Bundle b){}
            public void onActivityDestroyed(Activity a){detach(a);}
        });
    }
    /** For a single screen: call after the host Activity setContentView(). */
    public static synchronized void attach(Activity a){
        if(a==null||a.isFinishing()||a.isDestroyed()||bubbles.containsKey(a))return;
        FrameLayout root=a.findViewById(android.R.id.content);
        if(root==null)return;
        TextView button=new TextView(a);
        button.setText("GPS");
        button.setTextSize(14f);
        button.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        button.setTextColor(Color.WHITE);
        button.setGravity(Gravity.CENTER);
        button.setContentDescription("فتح لوحة XsGPS");
        button.setElevation(dp(a,12));
        GradientDrawable circle=new GradientDrawable(
            GradientDrawable.Orientation.TL_BR,new int[]{0xff40ceb3,0xff135b80});
        circle.setShape(GradientDrawable.OVAL);
        circle.setStroke(dp(a,2),Color.WHITE);
        button.setBackground(circle);
        int size=dp(a,56);
        FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(size,size,
             Gravity.END|Gravity.CENTER_VERTICAL);
        lp.setMargins(dp(a,12),dp(a,10),dp(a,14),dp(a,10));
        root.addView(button,lp);
        button.setOnTouchListener(new View.OnTouchListener(){
            float x0,y0,x1,y1;boolean dragged;
            public boolean onTouch(View v,MotionEvent e){
                switch(e.getActionMasked()){
                    case MotionEvent.ACTION_DOWN:
                        x0=e.getRawX();y0=e.getRawY();
                        x1=v.getTranslationX();y1=v.getTranslationY();
                        dragged=false;return true;
                    case MotionEvent.ACTION_MOVE:
                        float dx=e.getRawX()-x0,dy=e.getRawY()-y0;
                        if(Math.hypot(dx,dy)>dp(a,8))dragged=true;
                        if(dragged){v.setTranslationX(x1+dx);v.setTranslationY(y1+dy);}
                        return true;
                    case MotionEvent.ACTION_UP:
                        if(!dragged)show(a);
                        return true;
                    case MotionEvent.ACTION_CANCEL:return true;
                    default:return false;
                }
            }
        });
        bubbles.put(a,button);
    }
    public static synchronized void detach(Activity a){
        View button=bubbles.remove(a);
        if(button!=null&&button.getParent() instanceof ViewGroup)
            ((ViewGroup)button.getParent()).removeView(button);
    }
    public static void show(Activity a){
        if(a==null||a.isFinishing()||a.isDestroyed())return;
        new XsGpsPanel(a).show();
    }
    private static int dp(Context c,int x){
        return Math.round(c.getResources().getDisplayMetrics().density*x);
    }
}
