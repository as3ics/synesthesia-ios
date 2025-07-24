//
//  ContentView.swift
//  synesthesia
//
//  Created by as3six on 7/23/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            SynesthesiaWrapper() // <-- Your full-screen drawing view
        }
        .ignoresSafeArea() // <-- So SynesthesiaView goes full-screen
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
        .previewInterfaceOrientation(.landscapeLeft)
    }
}
