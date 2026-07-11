import Foundation

enum DateFormatters {
    static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm 'on' d MMM"
        return formatter
    }()
}
