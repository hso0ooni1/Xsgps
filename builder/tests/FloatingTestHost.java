package com.xsgps.android;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

/** Plain host with no XS GPS calls; startup must come from the merged provider. */
public final class MainActivity extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView text = new TextView(this);
        text.setText("XS GPS integration host");
        text.setTextSize(24);
        text.setGravity(17);
        setContentView(text);
    }
}
