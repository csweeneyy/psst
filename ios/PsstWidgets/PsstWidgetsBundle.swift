import SwiftUI
import WidgetKit

@main
struct PsstWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NudgeLiveActivity()
        PsstAlarmWidget()
        NextNudgeWidget()
        PsstLogControl()
    }
}
