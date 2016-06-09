# Loop for iOS

![App Icon](/Loop/Assets.xcassets/AppIcon.appiconset/40%402x.png?raw=true) ![WatchApp Icon](/WatchApp/Assets.xcassets/AppIcon.appiconset/watch-40%402x.png?raw=true)

[![Build Status](https://travis-ci.org/loudnate/Loop.svg?branch=master)](https://travis-ci.org/loudnate/Loop)
[![Join the chat at https://gitter.im/loudnate/LoopKit](https://badges.gitter.im/loudnate/LoopKit.svg)](https://gitter.im/loudnate/LoopKit?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Loop is an app template for building an artificial pancreas. It is a stone resting on the boulders of work done by [@bewest](https://github.com/bewest/decoding-carelink), [@ps2](https://github.com/ps2/rileylink) and many others.

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
<a href="/Documentation/Screenshots/Watch%20Notification%20Battery.png"><img src="/Documentation/Screenshots/Watch%20Notification%20Battery.png?raw=true" alt="Screenshot of bolus failure notification on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Notification%20Reservoir.png"><img src="/Documentation/Screenshots/Watch%20Notification%20Reservoir.png?raw=true" alt="Screenshot of bolus failure notification on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Notification%20Bolus%20Failure.png"><img src="/Documentation/Screenshots/Watch%20Notification%20Bolus%20Failure.png?raw=true" alt="Screenshot of bolus failure notification on Apple Watch" width="141"></a>

### Hardware

<table>
  <thead>
    <tr>
      <td colspan="2" rowspan="2"></td>
      <th colspan="2">Insulin Pump</th>
    </tr>
    <tr>
      <th>MM 522/722</th>
      <th>MM 523/723</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th rowspan="2">CGM</th>
      <th>Dexcom G4 + Share</th>
      <td>✅<sup><a href="#hw1">1</a> <a href="#hw2">2</a></sup></td>
      <td>✅<sup><a href="#hw1">1</a></sup></td>
    </tr>
    <tr>
      <th>Dexcom G5</th>
      <td>✅<sup><a href="#hw2">2</a></sup></td>
      <td>✅</td>
    </tr>
  </tbody>
</table>

<br/><a name="hw1">1</a>. Internet connection required to retrieve glucose
<br/><a name="hw2">2</a>. Pump must have a remote ID added in the [Remote Options](https://www.medtronicdiabetes.com/sites/default/files/library/download-library/workbooks/x22_menu_map.pdf) menu

### LoopKit

Loop is built on top of [LoopKit](https://github.com/loudnate/LoopKit). LoopKit is a set of frameworks that provide data storage, retrieval, and calcluation, as well as boilerplate view controllers used in Loop.

# Getting Started

Fork and clone this repository so you can commit the changes you'll make below.

## Assigning a Bundle Identifier

[![Assigning a bundle identifier](/Documentation/Assigning%20a%20bundle%20identifier.png?raw=true)](/Documentation/Assigning%20a%20bundle%20identifier.png)

In the Loop project's Build Settings, change the value of `MAIN_APP_BUNDLE_IDENTIFIER` to something unique. Usually this means replacing `com.loudnate` with a reverse-domain name of your choosing.

## Configuring RemoteSettings.plist

Loop optionally supports select third-party remote services. While none of them are required to run the app, including [mLab](https://mlab.com) keys is strongly recommended at this time so loop diagnostic data can be stored in case retrospective analysis is needed.

After a fresh clone of the repository, you'll need duplicate the template file and populate the copy with values.

```bash
$ cp Loop/RemoteSettings-template.plist Loop/RemoteSettings.plist
```

`RemoteSettings.plist` is included in `.gitignore` so you won't accidentally commit any sensitive keys.

| Key                    | Description
| ---------------------- | -------------
| `mLabAPIKey`           | Your mLab API Key (for tracking errors and diagnostic info)
| `mLabAPIHost`          | The mLab API host
| `mLabAPIPath`          | Your mLab database path
| `AmplitudeAPIKey`      | Your Amplitude analytics API Key (for optional, private behavior tracking)
| `ShareAccountName`     | Your username for Dexcom share (for backfilling glucose data)
| `ShareAccountPassword` | Your password for Dexcom share

## Setting up Carthage

[Carthage](https://github.com/carthage/carthage) is used to manage dependencies. If you haven't installed Carthage on your Mac before, [follow the installation instructions](https://github.com/carthage/carthage#installing-carthage).

After a fresh clone of the repository, you'll need to do a checkout and build of the dependencies:

```bash
$ carthage bootstrap
```

After pulling new changes, you'll need to run the same command again.

# Making it Your Own

You might open this app a lot. Make it the most personal app on your iPhone by changing the name and icon.

### Renaming the Target

[![Changing the target name](/Documentation/Changing%20the%20target%20name.png?raw=true)](/Documentation/Changing%20the%20target%20name.png)

In the Targets list, rename "Loop" to anything you like. This has the side-effect of changing the display name of the app as well, though you can choose to decouple those if you like later by reading more about Xcode target configuration.

### Changing the Icon

[![Changing the app icon](/Documentation/Changing%20the%20app%20icon.png?raw=true)](/Documentation/Changing%20the%20app%20icon.png)

1. Select the application asset library from the Project Navigator
2. Select the image set named AppIcon
3. Replace each image size with your own icon

Below are some example icons from other Loop users:

![Icon A](/Documentation/User Icons/LoopingPump.png?raw=true)

# Changing the code

TODO: Write more documentation!

# License and Code of Conduct

Please read the [LICENSE](/LICENSE) and [CODE_OF_CONDUCT](/CODE_OF_CONDUCT.md)
