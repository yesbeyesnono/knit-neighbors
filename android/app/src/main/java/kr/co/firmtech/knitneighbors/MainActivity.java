package kr.co.firmtech.knitneighbors;

import android.os.Bundle;
import android.webkit.WebSettings;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
  @Override
  public void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    // 폰의 '글자 크기' 설정과 무관하게 iOS 웹뷰와 같은 배율로 그린다(안드로이드만 글자가 커져 레이아웃이 깨지는 것 방지)
    WebSettings ws = getBridge().getWebView().getSettings();
    ws.setTextZoom(100);
  }
}
