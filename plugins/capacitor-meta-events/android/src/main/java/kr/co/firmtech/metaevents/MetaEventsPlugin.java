package kr.co.firmtech.metaevents;

import android.os.Bundle;
import com.facebook.appevents.AppEventsLogger;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.Iterator;

/**
 * Meta(Facebook) 앱 이벤트 — 설치·실행은 SDK 가 자동 기록(AndroidManifest meta-data AutoLogAppEventsEnabled),
 * 가입·친구 신청·모임 참여 같은 행동은 JS 에서 logEvent 로 보낸다.
 */
@CapacitorPlugin(name = "MetaEvents")
public class MetaEventsPlugin extends Plugin {

    private AppEventsLogger logger;

    @Override
    public void load() {
        logger = AppEventsLogger.newLogger(getContext());
    }

    @PluginMethod
    public void logEvent(PluginCall call) {
        String name = call.getString("name");
        if (name == null || name.isEmpty()) {
            call.reject("name 이 필요합니다");
            return;
        }
        JSObject params = call.getObject("params", new JSObject());
        Bundle bundle = new Bundle();
        Iterator<String> keys = params.keys();
        while (keys.hasNext()) {
            String k = keys.next();
            Object v = params.opt(k);
            if (v != null) bundle.putString(k, String.valueOf(v));
        }
        logger.logEvent(name, bundle);
        call.resolve();
    }
}
