# Loop for iOS

![App Icon](https://raw.githubusercontent.com/loudnate/Loop/master/Loop/Assets.xcassets/AppIcon.appiconset/40%402x.png) ![WatchApp Icon](https://raw.githubusercontent.com/loudnate/Loop/master/WatchApp/Assets.xcassets/AppIcon.appiconset/watch-40%402x.png)

[![Build Status](https://travis-ci.org/loudnate/Loop.svg?branch=master)](https://travis-ci.org/loudnate/Loop)
[![Join the chat at https://gitter.im/loudnate/LoopKit](https://badges.gitter.im/loudnate/LoopKit.svg)](https://gitter.im/loudnate/LoopKit?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

Loop is an app template for building an artificial pancreas. It is a stone resting on the boulders of work done by [@bewest](https://github.com/bewest/decoding-carelink), [@ps2](https://github.com/ps2/rileylink) and many others.

Please understand that this project:
- Is highly experimental
- Is not approved for therapy

### LoopKit

Loop is built on top of [LoopKit](https://github.com/loudnate/LoopKit). LoopKit is a set of frameworks that provide data storage, retrieval, and calcluation, as well as boilerplate view controllers used in Loop.

# Getting Started

Fork and clone this repository so you can commit the changes you'll make below.

## Assigning a Bundle Identifier

[![Assigning a bundle identifier](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Assigning%20a%20bundle%20identifier.png)](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Assigning%20a%20bundle%20identifier.png)

In the Loop project's Build Settings, change the value of `MAIN_APP_BUNDLE_IDENTIFIER` to something unique. Usually this means replacing `com.loudnate` with a reverse-domain name of your choosing.

## Configuring RemoteSettings.plist

Loop supports select third-party remote services. They are all technically optional. However, including [mLab](https://mlab.com) keys is strongly recommended at this time so loop diagnostic data can be stored in case retrospective analysis is needed.

After a fresh clone of the repository, you'll need duplicate the template file and populate the copy with values.

```bash
Loop$ cp Loop/RemoteSettings-template.plist Loop/RemoteSettings.plist
```

`RemoteSettings.plist` is included in `.gitignore` so you won't accidentally commit any sensitive keys.
Every one of these values is technically optional.

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

After a fresh clone of the repository, you'll need do an checkout and build of the dependencies:

```bash
Loop$ carthage bootstrap
```

After pulling new changes, you'll need to run the same command again.

# Making it Your Own

You might open this app a lot. Make it the most personal app on your iPhone by changing the name and icon.

### Renaming the Target

[![Changing the target name](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20target%20name.png)](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20target%20name.png)

In the Targets list, rename "Loop" to anything you like. This has the side-effect of changing the display name of the app as well, though you can choose to decouple those if you like later by reading more about Xcode target configuration.

### Changing the Icon

[![Changing the app icon](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20app%20icon.png)](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20app%20icon.png)

1. Select the application asset library from the Project Navigator
2. Select the image set named AppIcon
3. Replace each image size with your own icon

# Changing the code

TODO: Write more documentation!

# License and Code of Conduct

Please read the [LICENSE](https://github.com/loudnate/naterade-ios/blob/master/LICENSE) and [CODE_OF_CONDUCT](https://github.com/loudnate/naterade-ios/blob/master/CODE_OF_CONDUCT.md)
