import Foundation
import UIKit
import Capacitor
import FacebookCore

/// Meta(Facebook) 앱 이벤트 — 설치·실행은 SDK 가 자동 기록(Info.plist FacebookAutoLogAppEventsEnabled),
/// 가입·친구 신청·모임 참여 같은 행동은 JS 에서 logEvent 로 보낸다.
/// ATT(추적 허용) 팝업은 띄우지 않는다 → 동의하지 않은 사용자도 AEM/SKAdNetwork 집계 측정은 된다.
@objc(MetaEventsPlugin)
public class MetaEventsPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MetaEventsPlugin"
    public let jsName = "MetaEvents"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "logEvent", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
        DispatchQueue.main.async {
            _ = ApplicationDelegate.shared.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
            AppEvents.shared.activateApp()
        }
    }

    @objc func logEvent(_ call: CAPPluginCall) {
        guard let name = call.getString("name"), !name.isEmpty else {
            call.reject("name 이 필요합니다")
            return
        }
        let raw = call.getObject("params") ?? [:]
        var params: [AppEvents.ParameterName: Any] = [:]
        for (key, value) in raw {
            params[AppEvents.ParameterName(rawValue: key)] = "\(value)"
        }
        DispatchQueue.main.async {
            AppEvents.shared.logEvent(AppEvents.Name(rawValue: name), parameters: params)
            call.resolve()
        }
    }
}
