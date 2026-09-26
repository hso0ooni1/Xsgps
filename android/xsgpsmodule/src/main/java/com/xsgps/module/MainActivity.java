package com.xsgps.module;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import com.xsgps.embed.XsGpsOverlay;

public final class MainActivity extends Activity {
  @Override public void onCreate(Bundle state) {
    super.onCreate(state);
    LinearLayout layout = new LinearLayout(this);
    layout.setOrientation(LinearLayout.VERTICAL);
    TextView label = new TextView(this);
    label.setText("XsGPS Test Module - Android official mock location");
    layout.addView(label);
    Button start = new Button(this);
    start.setText("Open XsGPS");
    start.setOnClickListener(v -> XsGpsOverlay.show(this));
    layout.addView(start);
    setContentView(layout);
  }
}
