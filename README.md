# Loop for iOS

![App Icon](/Loop/Assets.xcassets/AppIcon.appiconset/Icon-40%402x.png?raw=true) ![WatchApp Icon](/WatchApp/Assets.xcassets/AppIcon.appiconset/watch-40%402x.png?raw=true)

[![Build Status](https://travis-ci.org/LoopKit/Loop.svg?branch=master)](https://travis-ci.org/LoopKit/Loop)
[![Join the chat at https://gitter.im/LoopKit/Loop](https://badges.gitter.im/LoopKit/Loop.svg)](https://gitter.im/LoopKit/Loop?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Loop is an app template for building an artificial pancreas. It is a stone resting on the boulders of work done by [@bewest](https://github.com/bewest/decoding-carelink), [@ps2](https://github.com/ps2/rileylink) and many others.

Loop is built on top of [LoopKit](https://github.com/LoopKit/LoopKit). LoopKit is a set of frameworks that provide data storage, retrieval, and calcluation, as well as boilerplate view controllers used in Loop.

Please understand that this project:
- Is highly experimental
- Is not approved for therapy

<a href="/Documentation/Screenshots/Phone%20Graphs.png"><img src="/Documentation/Screenshots/Phone%20Graphs.png?raw=true" alt="Screenshot of status screen" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Bolus.png"><img src="/Documentation/Screenshots/Phone%20Bolus.png?raw=true" alt="Screenshot of bolus screen" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Notification%20Battery.png"><img src="/Documentation/Screenshots/Phone%20Notification%20Battery.png?raw=true" alt="Screenshot of battery change notification" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Notification%20Loop%20Failure.png"><img src="/Documentation/Screenshots/Phone%20Notification%20Loop%20Failure.png?raw=true" alt="Screenshot of loop failure notification" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Notification%20Bolus%20Failure.png"><img src="/Documentation/Screenshots/Phone%20Notification%20Bolus%20Failure.png?raw=true" alt="Screenshot of bolus failure notification" width="170"></a>

<a href="/Documentation/Screenshots/Watch%20Complication.png"><img src="/Documentation/Screenshots/Watch%20Complication.png?raw=true" alt="Screenshot of glucose complication on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Carb%20Entry.png"><img src="/Documentation/Screenshots/Watch%20Carb%20Entry.png?raw=true" alt="Screenshot of carb entry on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Bolus.png"><img src="/Documentation/Screenshots/Watch%20Bolus.png?raw=true" alt="Screenshot of bolus entry on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Menu.png"><img src="/Documentation/Screenshots/Watch%20Menu.png?raw=true" alt="Screenshot of the app menu on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Notification%20Reservoir.png"><img src="/Documentation/Screenshots/Watch%20Notification%20Reservoir.png?raw=true" alt="Screenshot of bolus failure notification on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Notification%20Bolus%20Failure.png"><img src="/Documentation/Screenshots/Watch%20Notification%20Bolus%20Failure.png?raw=true" alt="Screenshot of bolus failure notification on Apple Watch" width="141"></a>

# Requirements

<table>
  <thead>
    <tr>
      <td colspan="2" rowspan="4"></td>
      <th colspan="3">Insulin Pump</th>
    </tr>
    <tr>
      <th>MM 522/722</th>
      <th>MM 523/723</th>
      <th>MM 554/754</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th rowspan="4">CGM</th>
      <th>Dexcom G4</th>
      <td>✅<sup><a href="#hw1">1</a> <a href="#hw2">2</a></sup></td>
      <td>✅<sup><a href="#hw1">1</a> <a href="#hw3">3</a></sup></sup></td>
      <td>✅<sup><a href="#hw1">1</a> <a href="#hw3">3</a></sup></sup></td>
    </tr>
    <tr>
      <th>Dexcom G5</th>
      <td>✅<sup><a href="#hw2">2</a></sup></td>
      <td>✅<sup><a href="#hw3">3</a></sup></td>
      <td>✅<sup><a href="#hw3">3</a></sup></td>
    </tr>
    <tr>
      <th>MM CGM</th>
      <td>❌<sup><a href="#hw4">4</a></sup></td>
      <td>✅<sup><a href="#hw3">3</a></sup></td>
      <td>✅<sup><a href="#hw3">3</a></sup></td>
    </tr>
  </tbody>
</table>

<br/><a name="hw1">1</a>. Offline access to glucose requires a Receiver with Share and the [Share2 app](https://itunes.apple.com/us/app/dexcom-share2/id834775275?mt=8) to be running on the same device. Internet-dependent access via Share servers is also supported.
<br/><a name="hw2">2</a>. Pump must have a remote ID added in the [Remote Options](https://www.medtronicdiabetes.com/sites/default/files/library/download-library/workbooks/x22_menu_map.pdf) menu.
<br/><a name="hw3">3</a>. Early firmware (US <= 2.4A, AU/EUR <= 2.6A) is required for using Closed Loop and Bolus features.
<br/><a name="hw4">4</a>. It's not impossible, but comms-heavy and there's some work to be done. File an issue if you're someone who's up for the challenge and can test this hardware configuration.

### Mac and Xcode

To build Loop you will need a Mac, and have Xcode 8 installed on it.  You will need to use git, either from the command line, or with a GUI like the Github Desktop Client.  You can build Loop without an Apple Developer Account, but any apps built this way will expire after a week, so signing up for the $99 developer account is recommended.

### iOS Phone

Loop will run on on any iPhone that is compatible with iOS 10.

### RileyLink

Bluetooth LE communication with Minimed pumps is enabled by the [RileyLink](https://github.com/ps2/rileylink), a compact BLE-to-916MHz bridge device designed by the incredible [@ps2](https://github.com/ps2). Please visit the [repository](https://github.com/ps2/rileylink) and the [gitter room](https://gitter.im/ps2/rileylink) for more information.

### Carthage

[Carthage](https://github.com/carthage/carthage) is used to manage framework dependencies. It will need to be [installed on your Mac](https://github.com/carthage/carthage#installing-carthage) to build and run the app, but most users won't have a need to explicitly rebuild any dependencies.

# Getting Started

Fork and clone this repository so you can commit the changes you'll make below.

[Sign up for the Loop Users announcement list](https://groups.google.com/forum/#!forum/loop-ios-users) to stay informed of critical issues that may arise.

## Assigning a Bundle Identifier

[![Assigning a bundle identifier](/Documentation/Assigning%20a%20bundle%20identifier.png?raw=true)](/Documentation/Assigning%20a%20bundle%20identifier.png)

Open `Loop.xcodeproj` in Xcode. In the Project Navigator on the left-hand side, open `Loop.xcconfig`. Change the value of `MAIN_APP_BUNDLE_IDENTIFIER` to a unique reverse-domain name of your choosing.

## Configuring Services

Loop optionally supports select third-party remote services, which are configured in the Settings screen.

| Service                | Description
| ---------------------- | -------------
| Dexcom Share           | Downloads glucose data if a local G5 Transmitter or G4 Receiver with Share is not available.
| Nightscout             | Uploads treatments and other pump data. Note that you will need to set "Nightscout history uploading" to "On" in Settings for treatments to be fetched from your pump and uploaded to Nightscout.
| mLab                   | Uploads diagnostic data about each loop run, as well as app errors. At this time, it is strongly recommended that you configure this service in case retrospective analysis is needed.
| Amplitude              | Tracks private, single-user behavioral and system analytics (no health data is sent)

# Making it Your Own

[Please visit the Wiki for more info on customizing the app](https://github.com/LoopKit/Loop/wiki/Personalizing-Your-App-Name-&-Icon)

# License and Code of Conduct

Please read the [LICENSE](/LICENSE.md) and [CODE_OF_CONDUCT](/CODE_OF_CONDUCT.md)
