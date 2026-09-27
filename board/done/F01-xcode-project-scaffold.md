# F01 - Xcode project scaffold

**Why**
Nothing runs until there is a buildable target. App target plus a widget extension, because both Live Activities and AlarmKit countdowns require a widget extension to exist.

**Acceptance**
- `xcodebuild -scheme Psst -destination 'platform=iOS Simulator,name=iPhone 17' build` succeeds
- App boots in the simulator and shows two tabs

**Notes**
Deployment target iOS 26.0. Bundle `com.connorsweeney.Psst`, widget `com.connorsweeney.Psst.Widgets`, app group `group.com.connorsweeney.Psst`.
