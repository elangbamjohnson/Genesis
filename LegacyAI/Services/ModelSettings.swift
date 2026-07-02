import Foundation

enum ModelSettings {
    static let defaultModelName = "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"

    static func normalizedModelName(_ modelName: String) -> String {
        let trimmedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmedName.lowercased() {
        case "", "qwen2.5-coder-14b", "qwen/qwen2.5-coder-14b":
            return defaultModelName
        default:
            return trimmedName
        }
    }
}
