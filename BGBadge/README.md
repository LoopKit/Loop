#BG Badge
BG Badge is a modification to Loop which will allow you to view your current BG value in mg/dl as a badge on your Loop icon.

![badge](https://github.com/CrushingT1D/Loop/blob/master/BGBadge/badge-sample.jpg)

By adding this to Loop, you will be presented with a switch in your settings where you can toggle the badge on and off.

![badge](https://github.com/CrushingT1D/Loop/blob/master/BGBadge/settings-switch-example.jpg)

If your BG value is stale or loop is in the "aging" state (loop has not run for over 5 minutes), then the BG will not show on your home icon. If I do not see a badge then I know that my loop may not be working properly and I can drill in to see what is going on. I do not make any decisions based upon the value of this badge and I always check BG in other places (Dexcom, finger stick, etc) before putting trust into the badge value.

There is an experimental, untested line of code for displaying the floor value in mmol (example 5.8 would display 5) included in the comments. If you'd like to try mmol you can uncomment it for testing and feedback. Would love to hear if you are able to get it working!

You can find the BG Badge code here: https://github.com/CrushingT1D/Loop/tree/bg-badge

You can see a comparison set of code changes between the current Loop/Master and Loop/bg-badge here: https://github.com/loudnate/Loop/compare/master...CrushingT1D:bg-badge

Please understand that this project:

* Is highly experimental
* Is not approved for therapy


