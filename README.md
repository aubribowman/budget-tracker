# Paycheck Plan for iPhone, iPad and Mac

A SwiftUI app that plans your budget one paycheck at a time: which bills each paycheck covers, what's left to spend, and how fast your debt and loans go away. It started as a port of the Paycheck Plan web app and still reads the same backup file, so a budget from the web app moves over in one step.

Runs on iOS 26, iPadOS 26 and macOS 26 or later. Free and open source under the [MIT License](LICENSE): build it for yourself, change it, or use parts of it in your own projects.

**Built with**

- **SwiftUI**, with one codebase for iPhone, iPad and Mac
- **WidgetKit** for home and lock screen widgets, sharing data with the app through an App Group
- **Swift Testing** for the budget math
- **Swift Charts** for the payoff chart and the spending breakdown
- No third-party code, no accounts and no server. Your budget stays on your devices.

## Screenshots

Shown with sample data.

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/home.png" width="220" alt="Home"><br><sub>Home</sub></td>
    <td align="center"><img src="docs/screenshots/paychecks.png" width="220" alt="Paychecks"><br><sub>Paychecks</sub></td>
    <td align="center"><img src="docs/screenshots/purchases.png" width="220" alt="Purchases"><br><sub>Purchases</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/month.png" width="220" alt="Month"><br><sub>Month</sub></td>
    <td align="center"><img src="docs/screenshots/review.png" width="220" alt="Monthly review"><br><sub>Monthly review</sub></td>
    <td align="center"><img src="docs/screenshots/payoff.png" width="220" alt="Payoff: debts"><br><sub>Payoff: debts</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/loans.png" width="220" alt="Payoff: student loans"><br><sub>Payoff: student loans</sub></td>
    <td align="center"><img src="docs/screenshots/goals.png" width="220" alt="Savings goals"><br><sub>Savings goals</sub></td>
    <td align="center"><img src="docs/screenshots/widget.png" width="180" alt="Home screen widget"><br><sub>Home screen widget</sub></td>
  </tr>
</table>

## What's in the app

### Tabs

- **Home**: what's left on this paycheck, your next payday, bills to pay now, spending left, debt, and savings goals. Each card folds to one line. The gear in the top corner opens **Setup**.
- **Paychecks**: every paycheck in the month with its bills grouped by type. Tap an item's circle to mark it paid (the same circle works in **To pay now** on Home and Paychecks), or long-press to set it aside. Every status change shows an **Undo** bar for a few seconds. Also autopay, moving a bill to another paycheck, skipping a month, one-time items, and pay-ahead. Paychecks and type groups fold. One-time items, extra income and **Use savings** are under **Add to this paycheck**.
- **Purchases**: spending categories stacked with what's left in each, logging purchases, moving them between categories, swipe to delete, and **Import from bank** in the **+** menu. Each purchase shows its store's first letter in a color worked out from the name, so the same store always looks the same.
- **Month**: what came in and went out, where your pay goes, and over-budget items. The clipboard button opens the **monthly review**.
- **Payoff**: two sections. Each debt shows the balance you entered and the payments marked paid since, so you can see where today's balance comes from.
  - **Debts**: your debt-free date, Avalanche, Snowball, or Pick a debt, the extra payment line on your paychecks, and **credit utilization**.
  - **Student loans**: what each loan grows to before repayment, standard payments, your payment plan, and payoff dates.

### Features

- **Bank import**: reads the CSV file you download from your bank and suggests where each transaction goes. See [Import from your bank](#import-from-your-bank).
- **Savings goals**: a target, what's saved, an optional target date, and whether you're on track. Link a savings item on your paychecks to a goal, and marking it paid moves the goal forward. When it's time to spend what you saved, **Use savings** (on a goal or a paycheck) adds the money to that paycheck as income, marks what it paid for as paid, and takes it off the goal, so what's left to spend doesn't change.
- **Credit utilization**: how much of your credit limits you're using overall and per card, and what to pay to get under 30% and 10%. Add a **Credit limit** to a card in its debt settings.
- **Monthly review**: plan vs. actual, each category over or under, bills not marked paid, debt paid, savings, and a comparison with the month before. Early each month, Home reminds you that last month's review is ready.
- **Windfall planner**: for a tax refund or bonus. On Home, tap **Got extra money? Plan it**. It suggests a split, shows how much sooner you'll be debt-free and how much interest you'll save, and can apply it to your balances.
- **Widgets**: small and medium home screen widgets on iPhone and iPad, plus lock screen widgets. They show what's left on your paycheck, bills due, days to payday, spending left, and your top goal.
- **Reminders**: a notification the day before each unpaid bill is due, and one on payday. Turn on in **Setup → Reminders**.
- **Face ID lock**: asks for Face ID or your passcode when you come back to the app, and hides balances in the app switcher. Turn on in **Setup → Privacy**.
- **Badges** on the tabs: Paychecks counts bills to pay now or past due, Purchases counts spending categories that are over, and Month shows a dot while last month's review is waiting.
- **Sidebar on Mac and iPad**, and a tab bar on iPhone.
- **Light and dark mode**, with app icons for both.
- **Accessibility**: layouts adjust for the largest text sizes, and VoiceOver reads each paycheck line as one item with its amount and status.
- **Privacy**: everything stays on the device and in the sync folder you choose. No accounts, tracking or analytics.

## Run it

You need Xcode 27 or later (free in the Mac App Store).

1. Get the code:
   ```bash
   git clone https://github.com/aubribowman/budget-tracker.git
   ```
2. Open `PaycheckApp.xcodeproj` in Xcode.
3. Pick an iPhone or iPad simulator from the device menu at the top of the window and press **⌘R**.

The app starts with a welcome card on Home: set your paydays, then add your bills and spending. Or tap **Restore from a backup** to load an existing budget (see [Move your data over](#move-your-data-over)).

To run the tests, press **⌘U**.

## Put it on your iPhone or iPad

1. Plug your iPhone or iPad into the Mac. On the phone, go to **Settings → Privacy & Security → Developer Mode** and turn it on. The phone restarts.
2. In Xcode, click the blue **PaycheckApp** project at the top of the sidebar. For both the **PaycheckApp** and **PaycheckWidget** targets, open **Signing & Capabilities**, check **Automatically manage signing**, and pick your **Team**.
3. Choose your device from the device menu and press **⌘R**. The first time, on the phone go to **Settings → General → VPN & Device Management** and trust your developer certificate.

### Use your own app ID

The app's ID is already taken by the original developer's account, so set your own before running on a device or Mac:

1. In Xcode, click the blue **PaycheckApp** project at the top of the sidebar, then the **PaycheckApp** project (not a target) in the list beside it.
2. Open **Build Settings**, search for `BUNDLE_ID_PREFIX`, and change `com.aubribowman` to something of your own, like `com.yourname`.

That one setting sets the app's ID (`com.yourname.PaycheckApp`), the widget's (`com.yourname.PaycheckApp.PaycheckWidget`) and the App Group they share (`group.com.yourname.PaycheckApp`). The code works out the App Group from the app's ID, so there's nothing else to change.

With a free Apple ID, the app stops opening after 7 days. Run it from Xcode again to reset that; your budget stays. The app reads its own expiry date and reminds you: a notification two days and one day before, a warning on Home in the last two days, and the date under **Setup → Reminders → Remind me to reinstall**, where you can turn the notification off. A paid Apple Developer account ($99/year) removes the limit and adds TestFlight.

## Run it on your Mac

Needs a Mac with an Apple chip.

1. In Xcode, pick **My Mac** from the device menu at the top of the window.
2. Press **⌘R**. The first time, Xcode sets up signing for the Mac the same way it does for your iPhone.

The Mac app has everything except widgets, which are iPhone and iPad only for now. Face ID becomes Touch ID on Macs that have it.

### Keep it in your Applications folder

Running from Xcode doesn't update the copy in Applications or the Dock. To build the app and put the latest version there, run this in Terminal from the project folder:

```bash
./scripts/install-mac.sh
```

It quits the app if it's open, moves the old copy to the Trash, installs the new one, and opens it. Your budget isn't touched. Run it again whenever you change the code. If it says the app didn't quit, a sheet or dialog is probably open in it: close it, or run the script with `--force`.

## Move your data over

1. In the web app, go to **Setup → Saving and backups → Download a backup**. Save or AirDrop the file to your iPhone's **Files** app.
2. In the app, tap **Restore from a backup** on the welcome card, or tap the gear on Home, then **Import a backup**, and choose the file.

To go the other way, use **Create a backup → Share backup file** in the app, then **Restore from a backup** in the web app.

## Keep your iPhone and Mac in sync

1. In the **Files** app on your iPhone (or Finder on your Mac), make a folder in **iCloud Drive**, for example `Paycheck Plan`.
2. In the app on each device, open **Setup → Sync between devices → Choose a sync folder** and pick that folder.
3. On the second device, the app finds the budget already there and asks which copy to keep. Choose **Use the folder's budget** to bring your existing plan over.

After that, each change is saved to a file named `Paycheck Plan.json` in that folder, and iCloud copies it to your other devices. The app checks for changes when it opens and every 30 seconds while it's open. **Sync now** checks right away.

- If you change both devices before they've had a chance to sync, the most recently saved copy wins and the other change is lost. Give iCloud a moment between devices.
- Sync works with a free Apple ID, because the app only uses a folder you pick. It doesn't need Apple's built-in iCloud sync.
- The sync file uses the same format as a backup, so you can also import it in the web app.

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
PaycheckApp/                  The app (iPhone and Mac)
  App/                        App entry and tabs, and Store: holds the budget, saves it, applies every change
  Model/                      The data, in the same format as the web app's backup file
  Engine/                     Budget math: paychecks, totals, debt payoff, student loans, goals
  Services/                   Sync folder, reminders, widget data, Face ID lock, bank CSV reader
  Shared/                     Colors, cards and other UI pieces used on several screens, and
                              Platform.swift (iPhone-only touches with their Mac versions)
  Utilities/                  Date and money helpers
  Screens/                    One folder per tab, one file per screen or sheet
    Home/                     Home and the windfall planner
    Paychecks/                Paychecks, the paycheck card, line details, one-time and extra income
    Purchases/                Purchases and bank import
    Month/                    Month and the monthly review
    Payoff/                   Debts, the payoff chart, student loans, credit utilization
    Goals/                    Savings goals
    Settings/                 Setup, pay schedule, recurring items, sync
  Resources/                  Fonts (Space Grotesk and DM Sans, with their licenses) and the
                              privacy manifest (PrivacyInfo.xcprivacy)
  Assets.xcassets             App icon (light and dark) and colors
PaycheckAppTests/             Tests for the budget math (run with ⌘U)
PaycheckWidget/               Home and lock screen widgets
Config/                       Entitlements (App Group, Mac file access for sync) and the widget's Info.plist
docs/screenshots/             Screenshots used in this README
scripts/install-mac.sh        Builds the Mac app and installs it in Applications
LICENSE                       MIT License
```

Xcode includes every file in `PaycheckApp/`, `PaycheckWidget/` and `PaycheckAppTests/` automatically, so you can add or move Swift files there without changing the project.

## How the code works

Data moves one way:

1. **`BudgetState`** ([Models.swift](PaycheckApp/Model/Models.swift)) is the whole budget, exactly as it's saved, synced and backed up.
2. **`Store`** ([Store.swift](PaycheckApp/App/Store.swift)) holds it and is the only thing that changes it. Every change goes through `store.update { ... }`, which saves and syncs.
3. **`Engine`** ([Engine.swift](PaycheckApp/Engine/Engine.swift)) works out the numbers from a snapshot: paydays, what's on each paycheck, totals, balances and payoff dates. It never changes the budget. The Store makes a new one after every change.
4. **Views** read `store.state` for data and `store.engine` for numbers, and call Store functions to make changes.

A paycheck is built like this: find the paydays in the month (`checksIn`), give each one a date range (`windowFor`), put each recurring item on the paycheck whose range holds its due date (`naturalRec`), add moved and one-time items (`lines`), then add it all up (`totals`). Changes for a single paycheck, like marking a bill paid, are stored as an `Override` on that paycheck, not on the recurring item.

### Things to keep in mind

- **Stay compatible with the web app.** The backup file is shared with the web app, so keep field names the same, decode new fields with a default, and don't remove fields the web app uses. The payoff math (`simulateAll` in [Engine+Loans.swift](PaycheckApp/Engine/Engine+Loans.swift)) is a port of the web app's, so both should show the same dates.
- **Dates are text.** Months are `"yyyy-MM"` and days are `"yyyy-MM-dd"`, compared as plain strings. Use the helpers in [DateUtil.swift](PaycheckApp/Utilities/DateUtil.swift).
- **Round money with `r2`** before saving it.
- **Balances count forward from when you entered them.** A debt or goal stores the balance you typed with `asOf` (the day) and `asOfAt` (the exact time). Today's balance is that number minus payments marked paid after it (`paidSince` in [Engine.swift](PaycheckApp/Engine/Engine.swift)), using each payment's `paidAt` time. Set `asOfAt` with `DU.stamp()` whenever you change a balance, or payments can be counted twice or not at all.
- **Status changes can be undone.** `Store.setStatus` saves the budget from before the change in `undoNote`, which shows the Undo bar ([UndoToast.swift](PaycheckApp/Shared/UndoToast.swift)) for 5 seconds.
- **Using savings makes linked items.** The income (`IncomeItem.goalId`) and the spending (`OneTime.useId`) are changed and deleted together through [BudgetState+Savings.swift](PaycheckApp/Model/BudgetState+Savings.swift), so the goal balance stays right. Go through the Store functions instead of editing them directly.
- **Use the shared styles.** [Theme.swift](PaycheckApp/Shared/Theme.swift) has the spacing steps (`Space`), corner sizes (`Radius`), `CardHeader` for card titles, and `heroNumber` / `rollingNumber` for money figures. Item icons come from [ItemIcon.swift](PaycheckApp/Shared/ItemIcon.swift), empty lists use `EmptyState`, and swipeable rows inside cards use `swipeRow` from [SwipeRow.swift](PaycheckApp/Shared/SwipeRow.swift). Name-and-amount rows use `ValueRow` ([ValueRow.swift](PaycheckApp/Shared/ValueRow.swift)), which stacks them at the largest text sizes. Tab titles use `PageTitle` and `.pageTitle` from [Platform.swift](PaycheckApp/Shared/Platform.swift), so they line up with the cards on iPad.
- **Run the tests after changing the math.** The tests in [PaycheckAppTests](PaycheckAppTests) check paydays, which paycheck each bill lands on, totals, rollover and payoff dates. Run them with Product → Test (⌘U).
- **iPhone vs. Mac.** Screens are shared. Put iPhone-only modifiers behind a helper in [Platform.swift](PaycheckApp/Shared/Platform.swift) with a Mac version, instead of adding `#if os(...)` in each screen.
- **Widget data.** If you change what the widget shows, update both `WidgetSync.Summary` in the app and `WidgetSummary` in the widget.
- **Privacy manifest.** [PrivacyInfo.xcprivacy](PaycheckApp/Resources/PrivacyInfo.xcprivacy) says the app doesn't track or collect data, and lists its one use of `UserDefaults`. Update it if you add an API Apple asks apps to explain, or a third-party SDK. It's also what the App Store needs, if you ever ship your own copy.

## Not yet

- **Widgets on Mac.** Widgets are built for iPhone and iPad only.
- **Automatic background sync.** Sync works through a folder you pick (see above). Apple's built-in iCloud sync, which needs no setup, requires a paid developer account.

## If the build fails

1. Try **Product → Clean Build Folder** (⇧⌘K) and build again.
2. If Xcode says **No Account for Team** or an ID is unavailable, see [Use your own app ID](#use-your-own-app-id) and pick your own **Team** under **Signing & Capabilities**.
3. If it still fails, open the **Issue navigator** (the triangle icon in Xcode's left sidebar) to see the errors. If you think it's a bug, open an issue on GitHub with the error messages.

## License

The code is under the [MIT License](LICENSE). The fonts, Space Grotesk and DM Sans, are under the SIL Open Font License; their license files are in [PaycheckApp/Resources/Fonts](PaycheckApp/Resources/Fonts).
