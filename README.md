# Paycheck Plan for iPhone

A native SwiftUI version of your Paycheck Plan web app. It reads the same backup file as the web app, so your budget moves over in one step.

## What's in Phase 1

- **Paychecks** with bills grouped by type, the three statuses (not paid, set aside, paid), autopay, moving bills between paychecks, skipping a month, one-time items, pay-ahead, and the "Pay from this paycheck" card.
- **Purchases** with category cards, logging, moving between categories, and swipe to delete.
- **Month** with what came in and went out, where your pay goes, and over-budget items.
- **Debt** with your debt-free date, Avalanche, Snowball or Pick a debt, and the extra payment line on your paychecks.
- **Setup** with pay schedule (semi-monthly, biweekly, or biweekly then semi-monthly), recurring items, backup import and export, and appearance.
- **Reminders**: a notification the day before each unpaid bill is due, and one on payday.

Coming in later phases: CSV bank import, Goals, student loans and the Payoff tab, the monthly review, windfall planner, utilization details, home screen widgets, and Face ID.

## Build it

You need Xcode (free in the Mac App Store) on your MacBook Air.

1. Open Xcode → **File → New → Project** → **iOS → App** → Next.
2. Product Name: **PaycheckPlan**. Interface: **SwiftUI**. Language: **Swift**. Storage: **None**. Uncheck tests. Save it anywhere.
3. In the left sidebar, delete the two files Xcode made: **ContentView.swift** and **PaycheckPlanApp.swift** (choose **Move to Trash**).
4. Unzip this download. Drag the **App**, **Model**, **Engine**, **Support** and **Views** folders from the inner `PaycheckPlan` folder into the yellow **PaycheckPlan** group in Xcode's sidebar. In the dialog, check **Copy items if needed** and **Create groups**, with the PaycheckPlan target checked.
5. Click the blue project icon at the top of the sidebar → **PaycheckPlan** target → **General** → set **Minimum Deployments** to **iOS 17.0**.
6. Pick an iPhone simulator at the top of the window and press **⌘R** to run.

## Put it on your iPhone

1. Plug your iPhone into the Mac. On the phone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
2. In Xcode: target → **Signing & Capabilities** → check **Automatically manage signing** → Team: **Add an Account…** and sign in with your Apple ID. Pick your **Personal Team**.
3. If Xcode says the bundle identifier is taken, change it to something unique, like `com.aubri.paycheckplan`.
4. Choose your iPhone at the top and press **⌘R**. The first time, on the phone go to **Settings → General → VPN & Device Management** and trust your developer certificate.

With a free Apple ID the app stops opening after 7 days; just run it from Xcode again. A paid Apple Developer account ($99/year) removes that limit and adds TestFlight.

## Move your data over

1. In the web app: **Setup → Saving and backups → Download a backup**. Save or AirDrop the file to your iPhone's **Files** app.
2. In the iPhone app: **Setup → Import a backup** → choose the file.

You can go the other way with **Create a backup → Share backup file**, then **Restore from a backup** in the web app.

## If the build fails

I wrote this without being able to run Xcode, so a few small errors are possible. In Xcode, open the **Issue navigator** (the triangle icon in the left sidebar), copy the red error messages with their file names, and paste them to me. I'll send fixes.
