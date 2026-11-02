# Paycheck Plan for iPhone

A native SwiftUI version of the Paycheck Plan web app. It plans your budget one paycheck at a time: which bills each paycheck covers, what's left to spend, and how fast your debt and loans go away. It reads the same backup file as the web app, so your budget moves over in one step.

## What's in the app

### Tabs

- **Home**: what's left on this paycheck, your next payday, bills to pay now, spending left, debt, and savings goals. Each card folds to one line. The gear in the top corner opens **Setup**.
- **Paychecks**: every paycheck in the month with its bills grouped by type. Each item can be not paid, set aside, or paid. Also autopay, moving a bill to another paycheck, skipping a month, one-time items, and pay-ahead. Paychecks and type groups fold.
- **Purchases**: spending categories stacked with what's left in each, logging purchases, moving them between categories, swipe to delete, and **Import from bank** in the **+** menu.
- **Month**: what came in and went out, where your pay goes, and over-budget items. The clipboard button opens the **monthly review**.
- **Payoff**: two sections.
  - **Debts**: your debt-free date, Avalanche, Snowball, or Pick a debt, the extra payment line on your paychecks, and **credit utilization**.
  - **Student loans**: what each loan grows to before repayment, standard payments, your payment plan, and payoff dates.

### Features

- **Bank import**: reads the CSV file you download from your bank and suggests where each transaction goes. See [Import from your bank](#import-from-your-bank).
- **Savings goals**: a target, what's saved, an optional target date, and whether you're on track. Link a savings item on your paychecks to a goal, and marking it paid moves the goal forward.
- **Credit utilization**: how much of your credit limits you're using overall and per card, and what to pay to get under 30% and 10%. Add a **Credit limit** to a card in its debt settings.
- **Monthly review**: plan vs. actual, each category over or under, bills not marked paid, debt paid, savings, and a comparison with the month before. Early each month, Home reminds you that last month's review is ready.
- **Windfall planner**: for a tax refund or bonus. On Home, tap **Got extra money? Plan it**. It suggests a split, shows how much sooner you'll be debt-free and how much interest you'll save, and can apply it to your balances.
- **Widgets**: small and medium home screen widgets, plus lock screen widgets. They show what's left on your paycheck, bills due, days to payday, spending left, and your top goal.
- **Reminders**: a notification the day before each unpaid bill is due, and one on payday. Turn on in **Setup → Reminders**.
- **Face ID lock**: asks for Face ID or your passcode when you come back to the app, and hides balances in the app switcher. Turn on in **Setup → Privacy**.
- **Light and dark mode**, with app icons for both.

## Run it

You need Xcode 27 or later (free in the Mac App Store).

1. Get the code:
   ```bash
   git clone https://github.com/aubribowman/budget-tracker.git
   ```
2. Open `PaycheckApp.xcodeproj` in Xcode.
3. Pick an iPhone simulator from the device menu at the top of the window and press **⌘R**.

The simulator starts with an empty budget. Import a backup (see below) to see your own numbers.

## Put it on your iPhone

1. Plug your iPhone into the Mac. On the phone, go to **Settings → Privacy & Security → Developer Mode** and turn it on. The phone restarts.
2. In Xcode, click the blue **PaycheckApp** project at the top of the sidebar. For both the **PaycheckApp** and **PaycheckWidget** targets, open **Signing & Capabilities**, check **Automatically manage signing**, and pick your **Team**.
3. Choose your iPhone from the device menu and press **⌘R**. The first time, on the phone go to **Settings → General → VPN & Device Management** and trust your developer certificate.

The app's ID is `com.aubribowman.PaycheckApp`, the widget's is `com.aubribowman.PaycheckApp.PaycheckWidget`, and they share data through the App Group `group.com.aubribowman.PaycheckApp`. If you sign with a different Apple account and Xcode says an ID is taken, change all three to your own (for example, swap `aubribowman` for your name). Make the same change in `PaycheckApp.entitlements`, `PaycheckWidget.entitlements`, `PaycheckApp/Support/WidgetSync.swift` and `PaycheckWidget/PaycheckWidget.swift`.

With a free Apple ID, the app stops opening after 7 days. Run it from Xcode again to reset that. A paid Apple Developer account ($99/year) removes the limit and adds TestFlight.

## Move your data over

1. In the web app, go to **Setup → Saving and backups → Download a backup**. Save or AirDrop the file to your iPhone's **Files** app.
2. In the iPhone app, tap the gear on Home, then **Import a backup**, and choose the file.

To go the other way, use **Create a backup → Share backup file** in the app, then **Restore from a backup** in the web app.

Your budget is saved only on the device. Nothing syncs between devices on its own, so use backups to move it.

## Import from your bank

1. On your bank's website, download your transactions as a **CSV** file and save it to the Files app.
2. In the app, on the **Purchases** tab, tap **+ → Import from bank**. You can also go to Setup → **Import from bank (CSV)**.
3. Check where each transaction goes:
   - a **spending category**, which logs it as a purchase
   - a **bill**, which marks that bill paid on the right paycheck at the amount you actually paid
   - **Skip**
4. Tap **Import**.

- **Suggestions:** the app suggests destinations from your saved rules, bill names, matching amounts, and, for Crew, pocket names.
- **Rules:** when you change a suggestion, **Always do this for…** saves a rule for that store.
- **No duplicates:** importing the same file again skips anything already imported.
- **Supported banks:** tested with Chase, Bank of America, Capital One, Wells Fargo, and Crew. Most other banks work too. If your spending shows up under **Money in**, turn on **Spending shows as positive**.
- **Crew files:** moves between pockets and pending charges are skipped automatically.

Rules and import history are kept separately from the web app's, so don't import the same transactions in both.

## Project layout

```
PaycheckApp/              The app
  App/                    App entry, tabs, Face ID lock, Store (saving and every change)
  Engine/                 Budget math: paychecks, lines, totals, debt payoff, goals, student loans
  Model/                  The data, in the same format as the web app's backup file
  Support/                Dates and money, colors, reminders, bank CSV reader, widget data
  Views/                  One file per screen
  Assets.xcassets         App icon (light and dark) and colors
PaycheckWidget/           Home and lock screen widgets
PaycheckWidget-Info.plist Widget settings
*.entitlements            App Group that lets the app and widget share data
```

## Not yet

- **Mac app.** The project targets the Mac, but a few iPhone-only parts (number keypads, title styles) need Mac versions before it builds there.
- **Sync** between devices. Today it's backups only. iCloud sync would need a paid developer account.

## If the build fails

1. Try **Product → Clean Build Folder** (⇧⌘K) and build again.
2. If it still fails, open the **Issue navigator** (the triangle icon in Xcode's left sidebar), copy the red error messages with their file names, and paste them to Claude.
