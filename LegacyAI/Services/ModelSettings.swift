import Foundation

enum ModelSettings {
    struct SupportedModel: Identifiable, Hashable {
        let id: String
        let displayName: String
        let description: String
    }

    static let qwenInstructModelName = "/Users/johnsonelangbam/.cache/huggingface/mlx-qwen25-14b-instruct"
    static let qwenCoderModelName = "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"

    static let defaultModelName = qwenInstructModelName

    static let supportedModels: [SupportedModel] = [
        SupportedModel(
            id: qwenInstructModelName,
            displayName: "Qwen2.5 14B Instruct (Local)",
            description: "Best default for conversational legacy answers. Loaded from your local MLX folder."
        ),
        SupportedModel(
            id: qwenCoderModelName,
            displayName: "Qwen2.5 Coder 14B Instruct",
            description: "Better for programming and technical explanations."
        )
    ]

    static func normalizedModelName(_ modelName: String) -> String {
        let trimmedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmedName.lowercased() {
        case "",
             "qwen2.5-14b",
             "qwen2.5-14b-instruct",
             "qwen/qwen2.5-14b",
             "qwen/qwen2.5-14b-instruct",
             "mlx-community/qwen2.5-14b-instruct-4bit",
             "/users/johnsonelangbam/.cache/huggingface/mlx-qwen25-14b-instruct",
             "~/.cache/huggingface/mlx-qwen25-14b-instruct":
            return qwenInstructModelName
        case "qwen2.5-coder-14b",
             "qwen2.5-coder-14b-instruct",
             "qwen/qwen2.5-coder-14b",
             "qwen/qwen2.5-coder-14b-instruct",
             "mlx-community/qwen2.5-coder-14b-instruct-4bit":
            return qwenCoderModelName
        default:
            return defaultModelName
        }
    }

    static func supportedModel(for modelName: String) -> SupportedModel {
        let normalizedName = normalizedModelName(modelName)
        return supportedModels.first { $0.id == normalizedName } ?? supportedModels[0]
    }
}
