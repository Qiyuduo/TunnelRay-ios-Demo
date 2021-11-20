import SwiftUI
import TunnelRay

struct ContentView: View {
    @StateObject var tunnel = TunnelRay_ios_lib();
    
    var body: some View {
        NavigationView {
            VStack {
                Button(tunnel.action) {
                    if(tunnel.action == "Connect"){
                        tunnel.connect()
                    } else {
                        tunnel.disconnect()
                    }
                }
                .padding(/*@START_MENU_TOKEN@*/.horizontal, 29.0/*@END_MENU_TOKEN@*/)
                .padding(.vertical, 5.0)
                .border(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/, width: /*@START_MENU_TOKEN@*/2/*@END_MENU_TOKEN@*/)
                Text(tunnel.status)
                    .padding()
                Text(tunnel.error)
                    .padding()
                NavigationLink(destination: WebViewPageView(redirectUrl: tunnel.redirectUrl), isActive: $tunnel.connected) {
                    EmptyView()
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
