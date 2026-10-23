# Loop for iOS

<img src="/Documentation/AppIcon.png?raw=true" alt="Loop app icon" width="128">

[![Join the chat at https://loop.zulipchat.com](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://loop.zulipchat.com)

Loop is an open-source automated insulin delivery app for iPhone and Apple Watch. It reads glucose from a continuous glucose monitor (CGM), forecasts glucose from insulin, carbs and recent trends, and adjusts delivery on a compatible insulin pump. It is a stone resting on the boulders of work done by many others.

Loop is built on [LoopKit](https://github.com/LoopKit/LoopKit), a set of frameworks for data storage, retrieval and calculation, and on [LoopAlgorithm](https://github.com/LoopKit/LoopAlgorithm). Pump and CGM support comes from separate plugins, and the app is built from [LoopWorkspace](https://github.com/LoopKit/LoopWorkspace).

Please understand that this project:
- Is highly experimental
- Is not approved for therapy

<a href="/Documentation/Screenshots/Phone%20Home.png"><img src="/Documentation/Screenshots/Phone%20Home.png?raw=true" alt="Status screen with glucose, active insulin and active carbs charts" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Bolus.png"><img src="/Documentation/Screenshots/Phone%20Bolus.png?raw=true" alt="Meal bolus screen with a recommended bolus" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Presets.png"><img src="/Documentation/Screenshots/Phone%20Presets.png?raw=true" alt="Presets screen" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Live%20Activity.jpg"><img src="/Documentation/Screenshots/Phone%20Live%20Activity.jpg?raw=true" alt="Live Activity on the Lock Screen" width="170"></a>

<a href="/Documentation/Screenshots/Phone%20Statistics.png"><img src="/Documentation/Screenshots/Phone%20Statistics.png?raw=true" alt="Statistics with glucose metrics and time in range" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Daily%20Insulin.png"><img src="/Documentation/Screenshots/Phone%20Daily%20Insulin.png?raw=true" alt="Daily insulin totals on the Statistics screen" width="170"></a>
<a href="/Documentation/Screenshots/Phone%20Add%20CGM.png"><img src="/Documentation/Screenshots/Phone%20Add%20CGM.png?raw=true" alt="Choosing a CGM" width="170"></a>

<a href="/Documentation/Screenshots/Watch%20Home.png"><img src="/Documentation/Screenshots/Watch%20Home.png?raw=true" alt="Apple Watch app" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Chart.png"><img src="/Documentation/Screenshots/Watch%20Chart.png?raw=true" alt="Glucose chart and forecast on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Carb%20Entry.png"><img src="/Documentation/Screenshots/Watch%20Carb%20Entry.png?raw=true" alt="Carb entry on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Bolus.png"><img src="/Documentation/Screenshots/Watch%20Bolus.png?raw=true" alt="Bolus on Apple Watch" width="141"></a>
<a href="/Documentation/Screenshots/Watch%20Presets.png"><img src="/Documentation/Screenshots/Watch%20Presets.png?raw=true" alt="Presets on Apple Watch" width="141"></a>

<sub>Screenshots are from the iOS Simulator with simulated CGM and pump data.</sub>

# Features

- **Automated insulin delivery.** Loop forecasts glucose several hours ahead and adjusts delivery with each new glucose reading, using either temporary basal rates or automatic boluses.
- **Meal and correction boluses** with a recommended amount and a forecast of where glucose is heading. Carb entries can include food type, absorption time and saved favorite foods.
- **Presets** that temporarily adjust insulin needs and correction range: pre-meal, your own custom presets, and built-in activity presets for walking, jogging, biking and strength training (which can be hidden). Presets can be scheduled, and in-app training explains how to use them.
- **Statistics**: GMI, average glucose, variability and time in range, an ambulatory glucose profile, and daily insulin totals split into basal, automatic bolus and manual bolus.
- **Live Activity** on the Lock Screen, in the Dynamic Island and on CarPlay.
- **Apple Watch app** with glucose and forecast, carb entry, bolus and presets.
- **Alerts** for glucose and device conditions, with urgent alerts that sound even when the phone is silenced or in a Focus.
- **Data sharing** with Apple Health, and upload to Nightscout and Tidepool through optional services.

# Supported devices

- **Pumps:** Omnipod 5, Omnipod DASH and Omnipod Classic (Eros, with RileyLink); older Medtronic pumps (with RileyLink); Medtrum Nano (200U and 300U).
- **CGMs:** Dexcom G5, G6, ONE, G7 and ONE+; FreeStyle Libre 1, 2 and 2+ (through MiaoMiao or Bubble transmitters, or EU Libre 2 directly); FreeStyle Libre 3 and 3+; Eversense E3 and 365; and readings from Dexcom Share or Nightscout.

See [Loop Docs](https://loopkit.github.io/loopdocs/) for the exact models and requirements.

# Documentation

Please visit the [Loop Docs](https://loopkit.github.io/loopdocs/) for installation, algorithm, and other details. Loop is built from [LoopWorkspace](https://github.com/LoopKit/LoopWorkspace), in a web browser with GitHub Actions or on a Mac with Xcode.

For FAQs, how to contribute to open source aspects of Loop and other tips, refer to the [Wiki](https://github.com/LoopKit/Loop/wiki).

Questions and discussion are welcome on [Loop Zulip](https://loop.zulipchat.com).

# License and Code of Conduct

Please read the [LICENSE](/LICENSE.md) and [CODE_OF_CONDUCT](/CODE_OF_CONDUCT.md)
