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
