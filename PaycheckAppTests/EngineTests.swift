import Foundation
import Testing
@testable import PaycheckApp

// Tests for the budget math in Engine. Each test builds a small made-up budget, so
// none of them touch your real data. Run them in Xcode with Product → Test (⌘U).
//
// Dates are in 2027 and the plan starts in 2027, so results don't depend on today's date.
// (Autopay is the one rule that looks at today; it isn't used here.)

/// A budget with semi-monthly pay on the 15th and the last day, $2,000 per check.
private func semiBudget(_ items: [Recurring] = []) -> BudgetState {
    var s = BudgetState()
    s.settings.mode = "semi"
    s.settings.payDay1 = 15
    s.settings.payDay2 = "last"
    s.settings.weekend = "friday"
    s.settings.pay = 2000
    s.settings.startMonth = "2027-01"
    s.recurring = items
    return s
}

/// A recurring item with only the fields a test needs. Defaults to a monthly bill paid
/// by due date ("auto").
private func item(_ name: String, _ amount: Double, type: String = "bill", due: String = "", when: String = "auto",
                  every: Int = 1, start: String = "") -> Recurring {
    var r = Recurring()
    r.name = name; r.type = type; r.amount = amount; r.due = due; r.when = when; r.every = every; r.start = start
    return r
}

@MainActor
struct PaydayTests {
    @Test func semiMonthlyPaydaysMoveOffWeekends() {
        let e = Engine(semiBudget())
        let checks = e.checksIn("2027-05")
        #expect(checks.count == 2)
        // May 15, 2027 is a Saturday, so it's paid the Friday before.
        #expect(DU.iso(checks[0].date) == "2027-05-14")
        #expect(DU.iso(checks[0].nominal) == "2027-05-15")
        #expect(DU.iso(checks[1].date) == "2027-05-31")
    }

    @Test func weekendSettingMonday() {
        var s = semiBudget()
        s.settings.weekend = "monday"
        #expect(DU.iso(Engine(s).checksIn("2027-05")[0].date) == "2027-05-17")
    }

    @Test func biweeklyMonthsHaveTwoOrThreePaydays() {
        var s = semiBudget()
        s.settings.mode = "biweekly"
        s.settings.bwAnchor = "2027-01-01"
        s.settings.bwPay = 1500
        let e = Engine(s)
        #expect(e.checksIn("2027-01").map { DU.iso($0.date) } == ["2027-01-01", "2027-01-15", "2027-01-29"])
        #expect(e.checksIn("2027-02").map { DU.iso($0.date) } == ["2027-02-12", "2027-02-26"])
        #expect(e.totals("2027-02", 1).income == 1500)
    }

    @Test func switchModeChangesToSemiMonthly() {
        var s = semiBudget()
        s.settings.mode = "switch"
        s.settings.bwAnchor = "2027-01-01"
        s.settings.switchMonth = "2027-03"
        let e = Engine(s)
        #expect(e.modeFor("2027-02") == "bw")
        #expect(e.modeFor("2027-03") == "semi")
    }
}

@MainActor
struct BillPlacementTests {
    @Test func billGoesOnThePaycheckBeforeItsDueDate() {
        let rent = item("Rent", 1200, due: "20")
        let e = Engine(semiBudget([rent]))
        // The 15th's paycheck covers the 15th up to the last day, so a bill due the 20th lands there.
        #expect(e.lines("2027-04", 1).map(\.id) == [rent.id])
        #expect(e.lines("2027-04", 2).isEmpty)
    }

    @Test func earlyMonthBillIsPaidFromLastMonthsSecondPaycheck() {
        let phone = item("Phone", 80, due: "3")
        let e = Engine(semiBudget([phone]))
        // The paycheck on Apr 30 covers Apr 30 to May 15, which holds May 3.
        let april2 = e.lines("2027-04", 2)
        #expect(april2.map(\.id) == [phone.id])
        #expect(april2.first.map { DU.iso($0.dueDate!) } == "2027-05-03")
    }

    @Test func pinnedItemsStayOnTheirPaycheck() {
        let gym = item("Gym", 40, type: "subscription", due: "20", when: "2")
        let e = Engine(semiBudget([gym]))
        #expect(e.lines("2027-04", 1).isEmpty)
        #expect(e.lines("2027-04", 2).map(\.id) == [gym.id])
    }

    @Test func everyPaycheckItemsShowOnBoth() {
        let groceries = item("Groceries", 200, type: "expense", when: "each")
        let e = Engine(semiBudget([groceries]))
        #expect(e.lines("2027-04", 1).count == 1)
        #expect(e.lines("2027-04", 2).count == 1)
    }

    @Test func quarterlyItemsOnlyShowEveryThirdMonth() {
        let water = item("Water", 90, when: "1", every: 3, start: "2027-01")
        let e = Engine(semiBudget([water]))
        let months = ["2027-01", "2027-02", "2027-03", "2027-04"].map { !e.lines($0, 1).isEmpty }
        #expect(months == [true, false, false, true])
    }

    @Test func movedBillShowsOnItsNewPaycheck() {
        let rent = item("Rent", 1200, due: "20")
        var s = semiBudget([rent])
        var cell = Cell()
        var o = Override(); o.moveTo = "2"
        cell.ov[rent.id] = o
        s.months["2027-04"] = ["1": cell]
        let e = Engine(s)
        #expect(e.lines("2027-04", 1).isEmpty)
        let moved = e.lines("2027-04", 2)
        #expect(moved.map(\.id) == [rent.id])
        #expect(moved.first?.moved == true)
    }
}

@MainActor
struct TotalsTests {
    @Test func leftIsTakeHomeMinusEverything() {
        let rent = item("Rent", 1200, due: "20")
        let power = item("Power", 150, due: "25")
        let t = Engine(semiBudget([rent, power])).totals("2027-04", 1)
        #expect(t.income == 2000)
        #expect(t.actual == 1350)
        #expect(t.left == 650)
    }

    @Test func skippedItemsDontCount() {
        let rent = item("Rent", 1200, due: "20")
        let power = item("Power", 150, due: "25")
        var s = semiBudget([rent, power])
        var cell = Cell()
        var o = Override(); o.skip = true
        cell.ov[power.id] = o
        s.months["2027-04"] = ["1": cell]
        #expect(Engine(s).totals("2027-04", 1).left == 800)
    }

    @Test func paidAndSetAsideAreTrackedSeparately() {
        let rent = item("Rent", 1200, due: "20")
        let power = item("Power", 150, due: "25")
        var s = semiBudget([rent, power])
        var cell = Cell()
        var paid = Override(); paid.paid = true
        var aside = Override(); aside.aside = true
        cell.ov[rent.id] = paid
        cell.ov[power.id] = aside
        s.months["2027-04"] = ["1": cell]
        let t = Engine(s).totals("2027-04", 1)
        #expect(t.paid == 1200)
        #expect(t.aside == 150)
    }

    @Test func overspendingCountsTheLargerAmount() {
        let groceries = item("Groceries", 200, type: "expense", when: "1")
        var s = semiBudget([groceries])
        var cell = Cell()
        var a = Buy(); a.amt = 180
        var b = Buy(); b.amt = 70
        cell.buys[groceries.id] = [a, b]
        s.months["2027-04"] = ["1": cell]
        let t = Engine(s).totals("2027-04", 1)
        #expect(t.budget == 200)
        #expect(t.actual == 250)
        #expect(t.left == 1750)
    }

    @Test func oneTimeItemsAndExtraIncomeCount() {
        var s = semiBudget()
        var cell = Cell()
        var gift = OneTime(); gift.name = "Gift"; gift.amount = 60
        var bonus = IncomeItem(); bonus.name = "Bonus"; bonus.amount = 500
        cell.extras = [gift]
        cell.addIncome = [bonus]
        cell.income = 2100
        s.months["2027-04"] = ["1": cell]
        let t = Engine(s).totals("2027-04", 1)
        #expect(t.income == 2600)
        #expect(t.extraIncome == 500)
        #expect(t.left == 2540)
    }

    @Test func rolloverCarriesLeftoverToTheNextPaycheck() {
        let rent = item("Rent", 1200, due: "20")
        var s = semiBudget([rent])
        s.settings.rollover = true
        s.settings.startMonth = "2027-04"   // so nothing carries in from before April
        let e = Engine(s)
        #expect(e.totals("2027-04", 1).start == 0)
        #expect(e.totals("2027-04", 1).left == 800)
        #expect(e.totals("2027-04", 2).start == 800)
    }

    @Test func monthTotalsAddUpBothPaychecks() {
        let rent = item("Rent", 1200, due: "20")
        let m = Engine(semiBudget([rent])).monthTotals("2027-04")
        #expect(m.income == 4000)
        #expect(m.actual == 1200)
        #expect(m.count == 2)
    }
}

@MainActor
struct DebtTests {
    /// A debt entered Jan 1, 2027, starting at its current balance.
    private func debt(_ name: String, balance: Double, apr: Double, min: Double) -> Debt {
        var d = Debt()
        d.name = name; d.balance = balance; d.original = balance; d.apr = apr; d.min = min; d.asOf = "2027-01-01"
        return d
    }

    @Test func zeroInterestDebtPaysOffOnSchedule() {
        var s = semiBudget()
        s.debts = [debt("Card", balance: 1000, apr: 0, min: 100)]
        let r = Engine(s).simulate(extra: 0, strategy: "avalanche")
        #expect(r.months == 10)
        #expect(r.interest == 0)
        #expect(!r.stuck)
    }

    @Test func extraPaymentsFinishSooner() {
        var s = semiBudget()
        s.debts = [debt("Card", balance: 3000, apr: 20, min: 90)]
        let e = Engine(s)
        let plain = e.simulate(extra: 0, strategy: "avalanche")
        let extra = e.simulate(extra: 200, strategy: "avalanche")
        #expect(extra.months < plain.months)
        #expect(extra.interest < plain.interest)
    }

    @Test func avalanchePaysHighestRateFirst() {
        var s = semiBudget()
        let low = debt("Low rate", balance: 500, apr: 5, min: 25)
        let high = debt("High rate", balance: 2000, apr: 25, min: 50)
        s.debts = [low, high]
        let r = Engine(s).simulate(extra: 300, strategy: "avalanche")
        #expect(r.payoff[high.id]! < r.payoff[low.id]!)
    }

    @Test func snowballPaysSmallestBalanceFirst() {
        var s = semiBudget()
        let small = debt("Small", balance: 500, apr: 5, min: 25)
        let big = debt("Big", balance: 2000, apr: 25, min: 50)
        s.debts = [small, big]
        let r = Engine(s).simulate(extra: 300, strategy: "snowball")
        #expect(r.payoff[small.id]! < r.payoff[big.id]!)
    }

    @Test func paymentTooSmallForInterestIsFlaggedAsStuck() {
        var s = semiBudget()
        s.debts = [debt("Card", balance: 10000, apr: 30, min: 50)]   // $250 a month in interest
        #expect(Engine(s).simulate(extra: 0, strategy: "avalanche").stuck)
    }

    @Test func standardLoanPayment() {
        // $10,000 at 6% over 10 years is $111.02 a month.
        #expect(Engine.standardPayment(10000, apr: 6, years: 10) == 111.02)
        #expect(Engine.standardPayment(1200, apr: 0, years: 1) == 100)
        #expect(Engine.standardPayment(0, apr: 6, years: 10) == 0)
    }
}

@MainActor
struct BackupTests {
    @Test func readsTheWebAppsLooseNumberFormats() throws {
        // The web app sometimes saves numbers as text. Both shapes must load.
        let json = """
        {"settings": {"payDay1": "1", "payDay2": 16, "pay": "1850.50", "rollover": 1},
         "recurring": [{"id": "rabc1234", "name": "Rent", "amount": "1200", "due": 1, "every": "0"}],
         "someFieldFromTheFuture": true}
        """
        let s = try JSONDecoder().decode(BudgetState.self, from: Data(json.utf8))
        #expect(s.settings.payDay1 == 1)
        #expect(s.settings.payDay2 == "16")
        #expect(s.settings.pay == 1850.5)
        #expect(s.settings.rollover)
        #expect(s.recurring.first?.amount == 1200)
        #expect(s.recurring.first?.due == "1")
        #expect(s.recurring.first?.every == 1)   // never less than 1
    }

    @Test func saveAndLoadGivesTheSameBudget() throws {
        var s = semiBudget([item("Rent", 1200, due: "20")])
        var cell = Cell()
        var b = Buy(); b.amt = 12.5; b.date = "2027-04-16"
        cell.buys["x"] = [b]
        s.months["2027-04"] = ["1": cell]
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(BudgetState.self, from: data) == s)
    }
}

/// Spending money saved in a goal (BudgetState+Savings.swift).
@MainActor
struct UseSavingsTests {
    /// A $500 babysitter fund and $1,200 rent on the first April paycheck.
    func budget() -> BudgetState {
        var s = semiBudget([item("Rent", 1200, due: "20")])
        var g = Goal(); g.name = "Babysitter fund"; g.target = 1000; g.balance = 500; g.asOf = "2027-01-01"
        s.goals = [g]
        return s
    }

    @Test func usingSavingsLeavesPaycheckLeftUnchanged() throws {
        var s = budget()
        let before = Engine(s).totals("2027-04", 1)
        let idResult = s.useSavings(goalId: s.goals[0].id, amount: 200, for: "Babysitter", type: "bill", key: "2027-04", n: 1)
        let id = try #require(idResult)
        let e = Engine(s)
        let t = e.totals("2027-04", 1)
        #expect(t.income == before.income + 200)
        #expect(t.extraIncome == 200)
        #expect(abs(t.left - before.left) < 0.005)
        // The goal goes down by what was used.
        #expect(e.goalStatus(s.goals[0]).saved == 300)
        // The spending is on the paycheck, paid, and says where the money came from.
        let line = try #require(e.lines("2027-04", 1).first { $0.name == "Babysitter" })
        #expect(line.paid)
        #expect(line.amount == 200)
        #expect(line.meta == "Paid from Babysitter fund")
        #expect(e.cell("2027-04", 1).addIncome.first?.id == id)
        #expect(e.cell("2027-04", 1).addIncome.first?.name == "From Babysitter fund")
    }

    @Test func deletingEitherPartPutsTheMoneyBack() throws {
        for removeSpending in [false, true] {
            var s = budget()
            let incomeIdResult = s.useSavings(goalId: s.goals[0].id, amount: 200, for: "Babysitter", type: "bill", key: "2027-04", n: 1)
            let incomeId = try #require(incomeIdResult)
            let spendId = try #require(s.months["2027-04"]?["1"]?.extras.first?.id)
            s.removeSavingsUse(key: "2027-04", n: 1, id: removeSpending ? spendId : incomeId)
            let c = Engine(s).cell("2027-04", 1)
            #expect(c.addIncome.isEmpty)
            #expect(c.extras.isEmpty)
            #expect(s.goals[0].balance == 500)
        }
    }

    @Test func changingTheAmountKeepsEverythingInStep() throws {
        var s = budget()
        let incomeIdResult = s.useSavings(goalId: s.goals[0].id, amount: 200, for: "Babysitter", type: "bill", key: "2027-04", n: 1)
        let incomeId = try #require(incomeIdResult)
        s.setSavingsUseAmount(key: "2027-04", n: 1, id: incomeId, to: 250)
        let c = Engine(s).cell("2027-04", 1)
        #expect(c.addIncome.first?.amount == 250)
        #expect(c.extras.first?.amount == 250)
        #expect(s.goals[0].balance == 250)
    }

    @Test func ordinaryItemsAreNotLinked() {
        var s = budget()
        var x = OneTime(); x.name = "Pizza"; x.amount = 20
        var inc = IncomeItem(); inc.name = "Refund"; inc.amount = 40
        s.months["2027-04"] = ["1": { var c = Cell(); c.extras = [x]; c.addIncome = [inc]; return c }()]
        let c = Engine(s).cell("2027-04", 1)
        #expect(s.savingsUseId(in: c, id: x.id) == nil)
        #expect(s.savingsUseId(in: c, id: inc.id) == nil)
        // Removing does nothing for items that aren't linked.
        s.removeSavingsUse(key: "2027-04", n: 1, id: x.id)
        #expect(Engine(s).cell("2027-04", 1).extras.count == 1)
        #expect(s.goals[0].balance == 500)
    }

    @Test func linksSurviveABackup() throws {
        var s = budget()
        _ = s.useSavings(goalId: s.goals[0].id, amount: 200, for: "Babysitter", type: "bill", key: "2027-04", n: 1)
        let back = try JSONDecoder().decode(BudgetState.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        let c = Engine(back).cell("2027-04", 1)
        #expect(c.addIncome.first?.goalId == s.goals[0].id)
        #expect(c.extras.first?.useId == c.addIncome.first?.id)
    }
}

/// Which payments lower a debt (or add to a goal): ones marked paid after its balance was entered.
@MainActor
struct BalanceSinceTests {
    /// A $1,000 card entered on payday (Apr 15, 2027) at 10:00, with its $50 minimum due the 20th.
    func budget() -> BudgetState {
        var card = item("Card minimum", 50, type: "debt", due: "20")
        var d = Debt(); d.name = "Card"; d.balance = 1000; d.min = 50; d.asOf = "2027-04-15"; d.asOfAt = "2027-04-15T10:00:00"
        card.debtId = d.id
        var s = semiBudget([card])
        s.debts = [d]
        return s
    }

    /// Marks the card payment paid on April paycheck `n`, at time `at` (nil = no time
    /// recorded, like a file saved before paid times existed).
    func markPaid(_ s: inout BudgetState, n: Int = 1, at: String?) {
        var o = Override(); o.paid = true; o.paidAt = at
        var m = s.months["2027-04"] ?? [:]
        var c = m[String(n)] ?? Cell()
        c.ov[s.recurring[0].id] = o
        m[String(n)] = c
        s.months["2027-04"] = m
    }

    @Test func paymentMarkedAfterTheBalanceCountsOnTheSameDay() {
        var s = budget()
        markPaid(&s, at: "2027-04-15T12:00:00")
        #expect(Engine(s).curBal(s.debts[0]) == 950)
    }

    @Test func paymentMarkedAfterTheBalanceCountsOnAnEarlierPaycheck() {
        var s = budget()
        s.debts[0].asOf = "2027-04-16"; s.debts[0].asOfAt = "2027-04-16T08:00:00"
        markPaid(&s, at: "2027-04-17T09:00:00")
        #expect(Engine(s).curBal(s.debts[0]) == 950)
    }

    @Test func paymentMarkedBeforeTheBalanceIsAlreadyInIt() {
        var s = budget()
        markPaid(&s, at: "2027-04-15T09:00:00")
        #expect(Engine(s).curBal(s.debts[0]) == 1000)
    }

    @Test func olderDataWithoutTimesUsesThePaycheckDate() {
        var s = budget()
        s.debts[0].asOfAt = nil
        markPaid(&s, at: nil)
        // Paycheck on the balance's date: already counted in it.
        #expect(Engine(s).curBal(s.debts[0]) == 1000)
        // Marked paid on a later day than the balance: counts.
        markPaid(&s, at: "2027-04-16T09:00:00")
        #expect(Engine(s).curBal(s.debts[0]) == 950)
    }

    @Test func goalsUseTheSameRule() {
        var save = item("Save", 100, type: "savings", due: "20")
        var g = Goal(); g.name = "Trip"; g.target = 1000; g.balance = 200; g.asOf = "2027-04-15"; g.asOfAt = "2027-04-15T10:00:00"
        save.goalId = g.id
        var s = semiBudget([save])
        s.goals = [g]
        markPaid(&s, at: "2027-04-15T11:00:00")
        #expect(Engine(s).goalStatus(s.goals[0]).saved == 300)
    }
}

/// The letter and color badge for a purchase's store.
struct MerchantBadgeTests {
    @Test func bankNamesAndTypedNamesMatch() throws {
        let imported = try #require(Merchant("SQ *KROGER #456 DUBLIN OH"))
        let typed = try #require(Merchant("Kroger"))
        #expect(imported.letter == "K")
        #expect(imported.key == typed.key)
        #expect(imported.color == typed.color)
    }

    @Test func lettersComeFromTheStoreName() {
        #expect(Merchant("Aldi")?.letter == "A")
        #expect(Merchant("trader joe's")?.letter == "T")
        #expect(Merchant("7-ELEVEN 33021")?.letter == "7")
        #expect(Merchant("AMZN Mktp US*2K4")?.letter == "A")
    }

    @Test func noNameMeansNoBadge() {
        #expect(Merchant("") == nil)
        #expect(Merchant("  ") == nil)
        #expect(Merchant("#1234") == nil)
    }

    @Test func colorsStayTheSameEveryLaunch() {
        // The color index comes from a fixed sum of the letters, so it can't change
        // between launches (Swift's hashValue would).
        let a = Merchant("Kroger")!.color, b = Merchant("Kroger")!.color
        #expect(a == b)
        #expect(Set(["kroger", "aldi", "shell", "target", "concert"].map { "\(Merchant($0)!.color)" }).count > 1)
    }
}

/// Reading when a free Apple ID install stops opening (AppExpiry.swift).
struct AppExpiryTests {
    /// A made-up profile: binary signature bytes around a property list, like the real file.
    func profile(_ plist: String) -> Data {
        Data([0x30, 0x80, 0x06, 0x09, 0x00, 0xFF]) + Data(plist.utf8) + Data([0x00, 0xA0, 0x82])
    }

    @Test func readsExpirationDate() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CreationDate</key><date>2026-11-04T02:01:16Z</date>
        <key>ExpirationDate</key><date>2026-11-11T02:01:16Z</date>
        </dict></plist>
        """
        let d = AppExpiry.expirationDate(inProfile: profile(xml))
        #expect(d == ISO8601DateFormatter().date(from: "2026-11-11T02:01:16Z"))
    }

    @Test func noDateInJunk() {
        #expect(AppExpiry.expirationDate(inProfile: Data("not a profile".utf8)) == nil)
    }

    @Test func labelSaysTodayAndTomorrow() {
        let hour = 3600.0
        let now = DU.date(2026, 11, 9).addingTimeInterval(9 * hour)
        #expect(AppExpiry.label(DU.date(2026, 11, 9).addingTimeInterval(21 * hour), now: now).hasPrefix("today at"))
        #expect(AppExpiry.label(DU.date(2026, 11, 10).addingTimeInterval(21 * hour), now: now).hasPrefix("tomorrow at"))
    }
}

#if os(macOS)
import SwiftUI
import Observation

/// Mac zoom (MacZoom in Platform.swift) works by making fonts bigger, so clicks always
/// land where you aim. These check the fonts grow and that screens hear about a change.
@MainActor
@Suite(.serialized)
struct MacZoomTests {
    /// The width of a line of app text, drawn at the current zoom.
    func textWidth() -> CGFloat {
        let r = ImageRenderer(content: Text("Paycheck Plan 1,234.56").font(.ui(.body)).fixedSize())
        return r.nsImage?.size.width ?? 0
    }

    @Test func zoomMakesTextBigger() {
        let old = ZoomLevel.shared.value
        defer { ZoomLevel.shared.value = old }
        ZoomLevel.shared.value = 1
        let normal = textWidth()
        ZoomLevel.shared.value = 1.5
        let zoomed = textWidth()
        #expect(normal > 0)
        #expect(zoomed > normal * 1.3)
    }

    @Test func changingZoomRedrawsText() {
        let old = ZoomLevel.shared.value
        defer { ZoomLevel.shared.value = old }
        var changed = false
        // Any view that reads a font while drawing is tracked like this, so it redraws.
        withObservationTracking { _ = Font.ui(.body) } onChange: { changed = true }
        ZoomLevel.shared.value = old + 0.15
        #expect(changed)
    }
}
#endif

/// When a card's statement closes next (Debt.nextStatement).
struct StatementDayTests {
    func card(_ day: Int?) -> Debt { var d = Debt(); d.statementDay = day; return d }

    @Test func laterThisMonth() {
        #expect(card(23).nextStatement(from: DU.date(2027, 4, 10)) == DU.date(2027, 4, 23))
    }

    @Test func todayCounts() {
        #expect(card(10).nextStatement(from: DU.date(2027, 4, 10)) == DU.date(2027, 4, 10))
    }

    @Test func passedRollsToNextMonth() {
        #expect(card(5).nextStatement(from: DU.date(2027, 4, 10)) == DU.date(2027, 5, 5))
        #expect(card(5).nextStatement(from: DU.date(2027, 12, 10)) == DU.date(2028, 1, 5))
    }

    @Test func shortMonthsUseTheLastDay() {
        #expect(card(31).nextStatement(from: DU.date(2027, 11, 2)) == DU.date(2027, 11, 30))
        #expect(card(30).nextStatement(from: DU.date(2027, 2, 2)) == DU.date(2027, 2, 28))
    }

    @Test func notSet() {
        #expect(card(nil).nextStatement(from: DU.date(2027, 4, 10)) == nil)
    }

    /// Saved as "statementDay" only when set, so the web app's file stays the same otherwise.
    @Test func savesOnlyWhenSet() throws {
        let without = String(decoding: try JSONEncoder().encode(card(nil)), as: UTF8.self)
        #expect(!without.contains("statementDay"))
        let back = try JSONDecoder().decode(Debt.self, from: JSONEncoder().encode(card(17)))
        #expect(back.statementDay == 17)
    }
}

/// Savings or one-time items used as a debt payment and linked to a debt lower that debt's
/// balance on Payoff. These use this month, since a payment marked paid "now" only counts
/// on paychecks Payoff looks at (through next month).
@MainActor
struct DebtFromSavingsTests {
    func budget() -> BudgetState {
        var s = semiBudget()
        s.settings.startMonth = DU.ym(Date())
        var g = Goal(); g.name = "Emergency fund"; g.target = 1000; g.balance = 600; g.asOf = "2020-01-01"
        var d = Debt(); d.name = "Card"; d.balance = 1000; d.min = 50; d.asOf = "2020-01-01"
        s.goals = [g]; s.debts = [d]
        return s
    }

    @Test func savingsLinkedToADebtLowersItsBalance() {
        var s = budget()
        s.useSavings(goalId: s.goals[0].id, amount: 300, for: "Card payment", type: "debt",
                     debtId: s.debts[0].id, key: DU.ym(Date()), n: 1)
        let e = Engine(s)
        #expect(e.curBal(s.debts[0]) == 700)
        #expect(s.goals[0].balance == 300)
    }

    @Test func savingsNotLinkedLeavesTheBalance() {
        var s = budget()
        s.useSavings(goalId: s.goals[0].id, amount: 300, for: "Card payment", type: "debt", key: DU.ym(Date()), n: 1)
        #expect(Engine(s).curBal(s.debts[0]) == 1000)
    }

    @Test func onlyDebtPaymentsKeepTheLink() {
        var s = budget()
        s.useSavings(goalId: s.goals[0].id, amount: 300, for: "Car repair", type: "bill",
                     debtId: s.debts[0].id, key: DU.ym(Date()), n: 1)
        #expect(s.months[DU.ym(Date())]?["1"]?.extras.first?.debtId == nil)
        #expect(Engine(s).curBal(s.debts[0]) == 1000)
    }

    @Test func removingTheUsePutsTheBalanceBack() throws {
        var s = budget()
        let key = DU.ym(Date())
        let result = s.useSavings(goalId: s.goals[0].id, amount: 300, for: "Card payment", type: "debt",
                                  debtId: s.debts[0].id, key: key, n: 1)
        let id = try #require(result)
        s.removeSavingsUse(key: key, n: 1, id: id)
        #expect(Engine(s).curBal(s.debts[0]) == 1000)
        #expect(s.goals[0].balance == 600)
    }
}

/// Amounts typed into the debt sheet, the way people write them.
@MainActor
struct TypedAmountTests {
    @Test func commasDollarSignsAndSpacesAreRead() {
        #expect(DebtEditSheet.number("1,250.00") == 1250)
        #expect(DebtEditSheet.number("$1,250") == 1250)
        #expect(DebtEditSheet.number(" 980.5 ") == 980.5)
        #expect(DebtEditSheet.number("abc") == nil)
    }
}

/// Reading Fidelity positions files (Positions → Download on fidelity.com).
@MainActor
struct FidelityCSVTests {
    /// The current layout, with made-up accounts: two funds and cash in one, a stock and
    /// pending activity in another, and the notes Fidelity adds at the bottom.
    static let newer = """
    Account Number,Account Name,Symbol,Description,Quantity,Last Price,Last Price Change,Current Value,Today's Gain/Loss Dollar,Today's Gain/Loss Percent,Total Gain/Loss Dollar,Total Gain/Loss Percent,Percent Of Account,Cost Basis Total,Average Cost Basis,Type
    Z11112222,Individual,FXAIX,FIDELITY 500 INDEX FUND,10.5,$200.00,+$1.20,"$2,100.00",+$12.60,+0.60%,+$600.00,+40.00%,70.00%,"$1,500.00",$142.86,Cash,
    Z11112222,Individual,SPAXX**,HELD IN MONEY MARKET,,,,$400.00,,,,,13.33%,,,Cash,
    Z11112222,Individual,FZROX,FIDELITY ZERO TOTAL MARKET,25,$20.00,-$0.10,$500.00,-$2.50,-0.50%,-$50.00,-9.09%,16.67%,$550.00,$22.00,Cash,
    123456789,ROTH IRA,AAPL,APPLE INC,4,$250.00,+$2.00,"$1,000.00",+$8.00,+0.80%,+$200.00,+25.00%,105.26%,$800.00,$200.00,Cash,
    123456789,ROTH IRA,Pending Activity,,,,,-$50.00,,,,,,,,,

    "The data and information in this spreadsheet is provided to you solely for your use."
    "Brokerage services are provided by Fidelity Brokerage Services LLC."

    "Date downloaded Nov-10-2026 3:45 p.m ET"
    """

    @Test func readsAccountsAndHoldings() throws {
        let a = try FidelityCSV.parse(Self.newer)
        #expect(a.count == 2)
        #expect(a[0].number == "Z11112222" && a[0].name == "Individual")
        #expect(a[0].holdings.count == 3)
        #expect(a[0].total == 3000)
        let fx = try #require(a[0].holdings.first { $0.symbol == "FXAIX" })
        #expect(fx.shares == 10.5 && fx.price == 200 && fx.cost == 1500 && !fx.cash)
        let cash = try #require(a[0].holdings.first { $0.symbol == "SPAXX" })
        #expect(cash.cash && cash.cost == nil)
        #expect(a[1].total == 950)   // $1,000 of Apple less $50 pending
        #expect(a[1].holdings.contains { $0.name == "Pending activity" && $0.cash })
    }

    @Test func readsTheOlderOneColumnLayout() throws {
        let text = """
        Account Name/Number,Symbol,Description,Quantity,Last Price,Current Value,Cost Basis Total
        ROTH IRA 123456789,FXAIX,FIDELITY 500 INDEX FUND,2,$100.00,$200.00,$150.00
        """
        let a = try FidelityCSV.parse(text)
        #expect(a.count == 1)
        #expect(a[0].number == "123456789" && a[0].name == "ROTH IRA")
        #expect(a[0].total == 200)
    }

    @Test func readsTheDownloadDate() {
        let d = FidelityCSV.downloaded(Self.newer)
        #expect(d.map(DU.iso) == "2026-11-10")
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: FidelityCSV.ParseError.self) { try FidelityCSV.parse("Date,Description,Amount\n11/01/2026,Coffee,-4.50") }
    }
}

/// Investment accounts: importing, contributions from paychecks, and net worth.
@MainActor
struct InvestmentTests {
    func budget() -> BudgetState {
        var s = semiBudget()
        s.settings.startMonth = DU.ym(Date())
        return s
    }

    @Test func importAddsAccountsThenUpdatesTheSameOnes() throws {
        var s = budget()
        let found = try FidelityCSV.parse(FidelityCSVTests.newer)
        s.importPositions(found, targets: Dictionary(uniqueKeysWithValues: found.map { ($0.key, "") }))
        #expect(s.accounts.count == 2)
        #expect(Engine(s).investTotal() == 3950)
        #expect(s.investHistory.count == 1 && s.investHistory[0].invest == 3950)

        // Next time, the same account numbers update those accounts instead of adding more.
        var again = found
        again[0].holdings = [Holding()]; again[0].holdings[0].value = 3500
        let targets = Dictionary(uniqueKeysWithValues: again.map { a in (a.key, s.accounts.first { $0.number == a.number }!.id) })
        s.importPositions(again, targets: targets)
        #expect(s.accounts.count == 2)
        #expect(Engine(s).investTotal() == 4450)
        #expect(s.investHistory.count == 1)   // one point per day
    }

    @Test func skippedAccountsAreLeftOut() throws {
        var s = budget()
        let found = try FidelityCSV.parse(FidelityCSVTests.newer)
        s.importPositions(found, targets: [found[0].key: ""])
        #expect(s.accounts.map(\.number) == ["Z11112222"])
    }

    @Test func paycheckContributionsAddUntilTheNextImport() {
        var s = budget()
        var a = InvestAccount(); a.name = "Roth IRA"; a.asOf = "2020-01-01"; a.asOfAt = nil
        var h = Holding(); h.value = 1000; a.holdings = [h]
        s.accounts = [a]
        var x = OneTime(); x.name = "IRA deposit"; x.type = "savings"; x.amount = 250
        x.paid = true; x.paidAt = DU.stamp(); x.goalId = a.id
        var c = Cell(); c.extras = [x]
        s.months[DU.ym(Date())] = ["1": c]
        #expect(Engine(s).accountValue(s.accounts[0]) == 1250)
        #expect(Engine(s).contributedSince(s.accounts[0]) == 250)
    }

    @Test func netWorthIsSavingsPlusInvestmentsMinusDebts() {
        var s = budget()
        var g = Goal(); g.balance = 500; g.target = 1000; g.asOf = "2020-01-01"
        var d = Debt(); d.balance = 300; d.asOf = "2020-01-01"
        var a = InvestAccount(); var h = Holding(); h.value = 2000; a.holdings = [h]
        s.goals = [g]; s.debts = [d]; s.accounts = [a]
        let nw = Engine(s).netWorth()
        #expect(nw.saved == 500 && nw.invested == 2000 && nw.owed == 300)
        #expect(nw.total == 2200)
    }

    @Test func deletingAnAccountUnlinksPaycheckItems() {
        var s = budget()
        let a = InvestAccount()
        var r = Recurring(); r.type = "savings"; r.goalId = a.id
        s.accounts = [a]; s.recurring = [r]
        s.deleteAccount(a.id)
        #expect(s.accounts.isEmpty && s.recurring[0].goalId == "")
    }

    @Test func accountsSurviveSavingAndLoading() throws {
        var s = budget()
        var a = InvestAccount(); a.name = "401(k)"; a.number = "X1"
        var h = Holding(); h.symbol = "FXAIX"; h.shares = 2; h.value = 400; h.cost = 300; a.holdings = [h]
        s.accounts = [a]
        s.recordValues()
        let back = try JSONDecoder().decode(BudgetState.self, from: JSONEncoder().encode(s))
        #expect(back.accounts == s.accounts)
        #expect(back.investHistory == s.investHistory)
    }
}

/// Daily prices from Tiingo, with a fake network so nothing is sent.
@MainActor
struct PriceTests {
    static func reply(_ code: Int, _ body: String) -> PriceService.Fetch {
        { req in (Data(body.utf8), HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: nil)!) }
    }

    @Test func symbolsUseHyphensForShareClasses() {
        #expect(PriceService.tiingoSymbol(" brk.b ") == "BRK-B")
        #expect(PriceService.tiingoSymbol("BF/B") == "BF-B")
        let r = PriceService.request(symbol: "FXAIX", key: "abc")!
        #expect(r.url?.absoluteString == "https://api.tiingo.com/tiingo/daily/FXAIX/prices")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Token abc")
        #expect(r.url?.absoluteString.contains("abc") == false)
    }

    @Test func readsTheLastClose() {
        let body = #"[{"date":"2026-11-06T00:00:00.000Z","close":210.5,"adjClose":210.5},{"date":"2026-11-09T00:00:00.000Z","close":212.25}]"#
        #expect(PriceService.parse(Data(body.utf8)) == .init(close: 212.25, date: "2026-11-09"))
        #expect(PriceService.parse(Data("[]".utf8)) == nil)
    }

    @Test func errorsAreSortedOut() async {
        let ok = #"[{"date":"2026-11-09T00:00:00.000Z","close":100}]"#
        var r = await PriceService.fetch(symbols: ["VTI", "FXAIX", "VTI"], key: "k", using: Self.reply(200, ok))
        #expect(r.quotes.count == 2 && r.error == nil)
        r = await PriceService.fetch(symbols: ["VTI"], key: "k", using: Self.reply(401, #"{"detail":"Invalid token."}"#))
        #expect(r.error == .badKey)
        r = await PriceService.fetch(symbols: ["VTI"], key: "k", using: Self.reply(429, ""))
        #expect(r.error == .tooMany)
        r = await PriceService.fetch(symbols: ["ZZZZ"], key: "k", using: Self.reply(404, #"{"detail":"Not found."}"#))
        #expect(r.missing == ["ZZZZ"] && r.error == nil)
        r = await PriceService.fetch(symbols: ["VTI"], key: " ", using: Self.reply(200, ok))
        #expect(r.error == .noKey)
    }

    @Test func pricesUpdateValuesButNotSharesOrCash() {
        var s = semiBudget()
        var a = InvestAccount()
        var fund = Holding(); fund.symbol = "FXAIX"; fund.shares = 10; fund.price = 200; fund.value = 2000; fund.cost = 1500
        var cash = Holding(); cash.symbol = "SPAXX"; cash.cash = true; cash.shares = 50; cash.price = 1; cash.value = 50
        a.holdings = [fund, cash]; a.asOf = "2026-11-01"
        s.accounts = [a]
        #expect(s.priceSymbols == ["FXAIX"])

        let q = ["FXAIX": PriceService.Quote(close: 212.345, date: "2026-11-09"), "SPAXX": .init(close: 2, date: "2026-11-09")]
        let changed = s.applyPrices(q)
        #expect(changed)
        let h = s.accounts[0].holdings
        #expect(h[0].value == 2123.45 && h[0].shares == 10 && h[0].priceAt == "2026-11-09")
        #expect(abs((h[0].gain ?? 0) - 623.45) < 0.001)
        #expect(h[1].value == 50)
        #expect(s.accounts[0].asOf == "2026-11-01")
        #expect(s.investHistory.last?.invest == 2173.45)
        let again = s.applyPrices(q)
        #expect(!again)   // same prices again: nothing to save
    }
}
