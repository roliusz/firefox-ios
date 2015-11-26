/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import CoreSpotlight
import WebKit


private let log = Logger.browserLogger
private let browsingActivityType: String = "org.mozilla.firefox.browsing"

class SpotlightHelper: NSObject {
    private(set) var activity: NSUserActivity? {
        willSet {
            log.info("invalidating \(activity?.webpageURL)")
            activity?.invalidate()
        }
        didSet {
            activity?.delegate = self
        }
    }

    private let createNewTab: ((url: NSURL) -> ())?

    private let profile: Profile!
    private weak var tab: Browser?

    init(browser: Browser, profile: Profile, openURL: ((url: NSURL) -> ())? = nil) {
        createNewTab = openURL
        self.profile = profile
        self.tab = browser

        if let path = NSBundle.mainBundle().pathForResource("SpotlightHelper", ofType: "js") {
            if let source = try? NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) as String {
                let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.AtDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    deinit {
        // Invalidate the currently held user activity (in willSet)
        // and release it.
        self.activity = nil
    }

    func updateIndexWith(url: NSURL, notification: [String: String]) {
        var activity: NSUserActivity
        if let currentActivity = self.activity where currentActivity.webpageURL == url {
            activity = currentActivity
        } else {
            activity = createUserActivity()
            self.activity = activity
            activity.webpageURL = url
        }

        activity.title = notification["title"]
        if #available(iOS 9, *) {
            if !(tab?.isPrivate ?? true) {
                let attrs = CSSearchableItemAttributeSet(itemContentType: kUTTypeHTML as String)
                attrs.contentDescription = notification["description"]

                if let favicons = tab?.favicons where !favicons.isEmpty {
                    print("Thumbnail!! \(favicons[0].url)")
                    attrs.thumbnailURL = NSURL(string: favicons[0].url)
                } else {
                    print("No thumbnail available for \(url.absoluteString)")
                }
                attrs.contentURL = url
                activity.contentAttributeSet = attrs
                activity.eligibleForSearch = true
            }
        }
        activity.becomeCurrent()
    }

    func becomeCurrent() {
        activity?.becomeCurrent()
    }

    func createUserActivity() -> NSUserActivity {
        return NSUserActivity(activityType: browsingActivityType)
    }
}

extension SpotlightHelper: NSUserActivityDelegate {
    @objc func userActivityWasContinued(userActivity: NSUserActivity) {
        log.info("userActivityWasContinued \(userActivity.webpageURL)")
        if let url = userActivity.webpageURL {
            createNewTab?(url: url)
        }
    }
}

extension SpotlightHelper: BrowserHelper {
    static func name() -> String {
        return "SpotlightHelper"
    }

    func scriptMessageHandlerName() -> String? {
        return "spotlightMessageHandler"
    }

    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let tab = self.tab,
            let url = tab.url,
            let payload = message.body as? [String: String] {
                updateIndexWith(url, notification: payload)
        }
    }
}
