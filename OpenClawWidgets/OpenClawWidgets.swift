//
//  OpenClawWidgets.swift
//  OpenClawWidgets
//
//  Widget bundle entry point registering all widgets.
//

import WidgetKit
import SwiftUI

@main
struct OpenClawWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodoWidget()
        NowPlayingWidget()
        DailyDashboardWidget()
    }
}
