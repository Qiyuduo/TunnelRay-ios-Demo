import Combine
import SwiftUI
import UIKit
import WebKit

@available(iOS 13.0.0, *)
struct WebViewPageView: View {
    var redirectUrl: String;
    private var webview = WKWebView(frame: .zero);
    
    init(redirectUrl: String) {
        self.redirectUrl = redirectUrl

        let url = URL(string: redirectUrl)!
        self.webview.load(URLRequest(url: url))
    }
    
    var body: some View {
        WebView(webView: webview)
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    @available(iOS 13.0.0, *)
    static var previews: some View {
        WebViewPageView(redirectUrl: "https://google.com")
    }
}
