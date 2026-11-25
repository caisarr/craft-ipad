import SwiftUI

enum CraftAppKind: String, CaseIterable, Identifiable {
    case gridcraft
    case pdfcraft
    case wordcraft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gridcraft: return "GridCraft"
        case .pdfcraft: return "PdfCraft"
        case .wordcraft: return "WordCraft"
        }
    }

    var subtitle: String {
        switch self {
        case .gridcraft: return "Spreadsheet"
        case .pdfcraft: return "PDF Editor & OCR"
        case .wordcraft: return "Documents"
        }
    }

    var sfSymbol: String {
        switch self {
        case .gridcraft: return "tablecells"
        case .pdfcraft: return "doc.richtext"
        case .wordcraft: return "doc.text"
        }
    }

    var folderName: String {
        rawValue
    }

    var accentColor: Color {
        switch self {
        case .gridcraft: return Color(red: 0.06, green: 0.72, blue: 0.51)
        case .pdfcraft: return Color(red: 0.96, green: 0.25, blue: 0.37)
        case .wordcraft: return Color(red: 0.23, green: 0.51, blue: 0.96)
        }
    }

    static func from(fileExtension ext: String) -> CraftAppKind? {
        switch ext.lowercased() {
        case "xlsx", "xlsm", "xls", "csv", "tsv", "ods":
            return .gridcraft
        case "pdf":
            return .pdfcraft
        case "docx", "doc", "rtf", "txt", "md", "odt":
            return .wordcraft
        default:
            return nil
        }
    }
}
