//
//  LiveWidgetBundle.swift
//  LiveWidget
//
//  Created by Kotaro Miyauchi on 2026/04/07.
//

import WidgetKit
import SwiftUI

@main
struct LiveWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveWidget()
        if #available(iOS 18.0, *) {
            LiveWidgetControl()
        }
        LiveWidgetLiveActivity()
    }
}
