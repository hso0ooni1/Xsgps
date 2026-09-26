package com.xsgps.embed;

import android.app.Application;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;

/** Registers the visible in-app panel without editing host Activity bytecode. */
public final class XsGpsInitProvider extends ContentProvider {
    @Override public boolean onCreate() {
        if (getContext() != null && getContext().getApplicationContext() instanceof Application) {
            XsGpsOverlay.install((Application) getContext().getApplicationContext());
            return true;
        }
        return false;
    }
    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri u) { return null; }
    @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
}
