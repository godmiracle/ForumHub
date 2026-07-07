import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let sessionChannelName = "forumhub/session"
  private var sessionChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ForumHubSessionBridge") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: sessionChannelName,
      binaryMessenger: registrar.messenger()
    )
    sessionChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCookieHeader":
      guard let arguments = call.arguments as? [String: Any],
            let rawURL = arguments["url"] as? String,
            let url = URL(string: rawURL)
      else {
        result("")
        return
      }

      let scopedCookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
      let header = HTTPCookie.requestHeaderFields(with: scopedCookies)["Cookie"] ?? ""
      result(header)
    case "readNgaLoginState":
      result(loginStatePayload(cookies: ngaCookies(from: HTTPCookieStorage.shared.cookies ?? [])))
    case "refreshNgaLoginState":
      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      cookieStore.getAllCookies { cookies in
        let ngaCookies = self.ngaCookies(from: cookies)
        for cookie in ngaCookies {
          HTTPCookieStorage.shared.setCookie(cookie)
        }
        result(self.loginStatePayload(cookies: ngaCookies))
      }
    case "syncNgaLoginCookies":
      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      cookieStore.getAllCookies { cookies in
        let ngaCookies = self.ngaCookies(from: cookies)
        for cookie in ngaCookies {
          HTTPCookieStorage.shared.setCookie(cookie)
        }
        result(self.loginStatePayload(cookies: ngaCookies))
      }
    case "clearNgaLoginCookies":
      let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
      for cookie in ngaCookies(from: sharedCookies) {
        HTTPCookieStorage.shared.deleteCookie(cookie)
      }

      let cookieStore = WKWebsiteDataStore.default().httpCookieStore
      cookieStore.getAllCookies { cookies in
        let ngaCookies = self.ngaCookies(from: cookies)
        let group = DispatchGroup()

        for cookie in ngaCookies {
          group.enter()
          cookieStore.delete(cookie) {
            group.leave()
          }
        }

        group.notify(queue: .main) {
          result(nil)
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func ngaCookies(from cookies: [HTTPCookie]) -> [HTTPCookie] {
    return cookies.filter { cookie in
      let domain = cookie.domain.lowercased()
      return domain.contains("nga.cn") || domain.contains("178.com")
    }
  }

  private func loginStatePayload(cookies: [HTTPCookie]) -> [String: Any] {
    let uid = cookies.first(where: { $0.name == "ngaPassportUid" })?.value
    let cid = cookies.first(where: { $0.name == "ngaPassportCid" })?.value
    let cookieNames = cookies
      .map(\.name)
      .filter { name in
        let lowered = name.lowercased()
        return lowered.contains("nga") || lowered.contains("guest") || lowered.contains("last")
      }
      .sorted()

    return [
      "uid": uid as Any,
      "cid": cid as Any,
      "cookieNames": cookieNames,
    ]
  }
}
