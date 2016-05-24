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

## Making It Your Own

Fork and clone this repository so you can commit the changes you'll make below.

### Assigning a Bundle Identifier

[![Assigning a bundle identifier](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Assigning%20a%20bundle%20identifier.png)](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Assigning%20a%20bundle%20identifier.png)

In the Loop project's Build Settings, change the value of `MAIN_APP_BUNDLE_IDENTIFIER` to something unique. Usually this means replacing `com.loudnate` with a reverse-domain name of your choosing.

### Renaming The Target

[![Changing the target name](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20target%20name.png)](https://raw.githubusercontent.com/loudnate/Loop/master/Documentation/Changing%20the%20target%20name.png)

In the Targets list, rename "Loop" to anything you like. This has the side-effect of changing the display name of the app as well, though you can choose to decouple those if you like later by reading more about Xcode target configuration.

## Changing the code

TODO: Write more documentation!

# License and Code of Conduct

Please read the [LICENSE](https://github.com/loudnate/naterade-ios/blob/master/LICENSE) and [CODE_OF_CONDUCT](https://github.com/loudnate/naterade-ios/blob/master/CODE_OF_CONDUCT.md)