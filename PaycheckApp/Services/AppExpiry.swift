import Foundation

/// When this copy of the app stops opening, for reminding you to reinstall it.
///
/// An app run from Xcode with a free Apple ID only works for 7 days. Xcode puts a
/// provisioning profile (`embedded.mobileprovision`) inside the app, and its
/// `ExpirationDate` is the moment the app stops opening. A paid developer account's
/// profile lasts a year. Simulator, TestFlight and App Store builds have no profile,
/// so `date` is nil there and nothing about expiring is shown.
///
/// iPhone and iPad only: a Mac app keeps opening after its profile runs out.
enum AppExpiry {
    /// Turns the reinstall reminder notification on or off (Setup → Reminders). On by default.
    static let reminderKey = "expiryReminderOn"
    static var reminderOn: Bool { UserDefaults.standard.object(forKey: reminderKey) as? Bool ?? true }

    /// Home shows a warning this many days before the app expires.
    static let warnDays = 2

    /// When the app stops opening, or nil if it doesn't expire this way. Read once per launch.
    static let date: Date? = {
        #if os(iOS)
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return expirationDate(inProfile: data)
        #else
        return nil
        #endif
    }()

    /// The profile is a signed file with a plain-text property list inside it. Rather than
    /// checking the signature (iOS already did that when installing), pull out the list
    /// between "<?xml" and "</plist>" and read `ExpirationDate` from it.
    static func expirationDate(inProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil),
              let dict = plist as? [String: Any] else { return nil }
        return dict["ExpirationDate"] as? Date
    }

    /// True in the last `warnDays` days before the app expires.
    static func isSoon(now: Date = Date()) -> Bool {
        guard let d = date else { return false }
        return d > now && d.timeIntervalSince(now) < Double(warnDays) * 86_400
    }

    /// "today at 9:01 PM", "tomorrow at 9:01 PM", "Thursday at 9:01 PM" within a week,
    /// otherwise "Nov 11 at 9:01 PM". `now` is when the text will be read (a notification's
    /// fire time), so "tomorrow" is right then.
    static func label(_ d: Date, now: Date = Date()) -> String {
        let time = d.formatted(date: .omitted, time: .shortened)
        switch DU.days(now, d) {
        case 0: return "today at \(time)"
        case 1: return "tomorrow at \(time)"
        case 2...6: return d.formatted(.dateTime.weekday(.wide)) + " at \(time)"
        default: return d.formatted(.dateTime.month(.abbreviated).day()) + " at \(time)"
        }
    }
}
