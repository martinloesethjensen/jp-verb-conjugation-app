import Foundation

/// The date strings the Word Bank puts in file names and import notes. Fixed and
/// locale-independent: an exported file's name must not change with the device's region.
enum WordBankDates {
    /// `yyyy-MM-dd`, for export names and the day an import was merged.
    static func day(_ date: Date) -> String {
        string(from: date, format: "yyyy-MM-dd")
    }

    /// `yyyy-MM-dd HH.mm.ss`, so backups taken the same day keep distinct names.
    static func timestamp(_ date: Date) -> String {
        string(from: date, format: "yyyy-MM-dd HH.mm.ss")
    }

    private static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
