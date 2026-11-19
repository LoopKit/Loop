# Building Loop with Xcode Cloud

An alternative to the GitHub Actions "browser build" and the local Mac/Xcode build. Xcode Cloud is Apple's hosted CI service: it clones your fork of `LoopWorkspace`, builds and signs the archive using certificates Apple manages for you, and delivers the result to TestFlight. No self-managed signing certificates, no repository secrets, no `fastlane match`, no personal access tokens.

---

### Prerequisites

- A paid **Apple Developer Program** membership. Xcode Cloud is not available on a free account.
- A **Mac with Xcode** (a current release). You need it once, to create the first workflow; after that, builds run on Apple's infrastructure and you can trigger and monitor them from App Store Connect or the iOS/iPadOS App Store Connect app.
- A **fork of `LoopWorkspace`** on GitHub that you can push to.
- **Account Holder or Admin** role in App Store Connect, to enable Xcode Cloud the first time.
- Apple includes 25 compute hours per month with the developer program at no extra cost. A full Loop archive typically consumes a meaningful fraction of an hour, so this is comfortable for personal use but not unlimited. Check current allowances in App Store Connect.

---

### Step 1 — Fork and clone

Fork `LoopKit/LoopWorkspace` to your own account, then clone your fork with submodules:

```bash
git clone --branch=dev --recurse-submodules https://github.com/<your-username>/LoopWorkspace
cd LoopWorkspace
xed .
```

Xcode Cloud builds from the remote repository, not from your working copy, so anything the build needs has to be committed and pushed to your fork.

### Step 2 — Set your development team (optional)

Xcode Cloud applies your development team automatically when it signs, so cloud builds need no source changes at all — `Loop.xcconfig` builds the bundle ID as `com.${DEVELOPMENT_TEAM}.loopkit`, so your app and all of its extensions get identifiers that are unique to your team without any edits.

If you also want to build locally (see Step 3), select `LoopConfigOverride.xcconfig` in Xcode's project navigator (it's in the root of the workspace) and uncomment the last line, replacing the value with your own Team ID from [developer.apple.com](https://developer.apple.com):

```
// Put your team id here for signing
LOOP_DEVELOPMENT_TEAM = ABCDE12345
```

Only local builds read this, so there's no need to commit it.

### Step 3 — Build locally once

Select the **LoopWorkspace** scheme (not the `Loop` scheme) and build to a real device. This requires the team ID from Step 2.

This is not strictly part of Xcode Cloud setup, but it's the cheapest way to get Xcode's automatic signing to register your App IDs, the `group.com.<TEAMID>.loopkit.LoopGroup` app group, and the rest of the capabilities in the developer portal. Doing it locally surfaces identifier and entitlement problems in seconds instead of in a cloud build several minutes long.

### Step 4 — Create the workflow

In Xcode, choose **Integrate → Create Workflow** (or **Product → Xcode Cloud → Create Workflow**).

1. **Product:** pick the Loop app from the workspace.
2. **Grant source access:** connect your GitHub account and authorize your `LoopWorkspace` fork. The sheet also lists the workspace's public package dependencies (`apple/swift-log`, `Kitura/*`, and so on) — leave them "Not connected." Public repositories need no access grant, and clicking **Connect…** on a repository you don't administer fails with an admin-permissions error.
3. **Workflow settings:**
   - **Scheme:** `LoopWorkspace`. It's a shared scheme in the repository, so Xcode Cloud can see it.
   - **Environment:** pick an Xcode version that can build the branch you're on.
   - **Start Conditions:** for a personal build, "Manual" or "Branch Changes" on your working branch is usually what you want. Delete the default "Pull Request Changes" condition unless you actually want PRs building against your quota.
   - **Actions:** an **Archive** action with distribution preparation set to
    - **TestFlight (Internal Testing Only)**. Remove the Build or Test actions if you don't want to spend compute hours on them.
   - **Post-Actions:** TestFlight internal testing, with yourself in the group.

If the TestFlight option doesn't appear in the initial wizard, create an Archive-only workflow first, run one build, then edit the workflow and add it.

4. **App record:** Xcode Cloud will offer to register the bundle identifier and create the App Store Connect record if one doesn't exist. Let it.

### Step 5 — Start a build

Trigger the workflow from Xcode's Cloud tab, from App Store Connect, or by pushing to the branch you configured. Logs stream live. On success the build shows up under TestFlight within a few minutes, and you install it from the TestFlight app on your phone.

---

## Keeping current

Xcode Cloud has no equivalent of the browser build's "keep alive" and auto-update jobs, so staying current is on you:

- **New Loop releases:** merge upstream `LoopKit/LoopWorkspace` into your fork. If your workflow starts on branch changes, the merge itself triggers the build.
- **TestFlight expiry:** internal TestFlight builds expire 90 days after upload. Add a **Scheduled** start condition (for example, monthly) to produce a fresh build off the same code and reset the clock. A scheduled build costs compute hours, so pick an interval, not a nightly cron.
---

## How this compares to the browser build

| | GitHub Actions (browser build) | Xcode Cloud |
| --- | --- | --- |
| Mac required | No | Yes, for initial workflow creation |
| Signing | `fastlane match`, certificates in a private repo you manage | Managed by Apple |
| Secrets to configure | Team ID, App Store Connect API key, match password, PAT | None |
| Cost | Free tier of GitHub Actions | 25 compute hours/month included with the developer program |
| Auto-update / keep-alive | Built into the workflows | Manual merges, or a scheduled start condition |
| Where builds land | TestFlight | TestFlight |

Both paths require a paid Apple Developer Program membership. Neither replaces the other — all three options (browser build, local Xcode build, Xcode Cloud) work from the same, unmodified source tree.
