import Foundation

/// 分类错误并提供可操作的用户友好提示
struct AppError: Error, Equatable {
    let category: Category
    let message: String
    let recoverySuggestion: String?
    let underlyingError: Error?

    enum Category: Equatable {
        case network          // 网络/连接问题
        case auth             // 认证/授权问题
        case server           // 服务端错误
        case parsing          // 解析/格式错误
        case audio            // 音频播放/合成错误
        case storage          // 存储/磁盘错误
        case validation       // 输入验证错误
        case unknown          // 未分类
    }

    init(category: Category, message: String, recoverySuggestion: String? = nil, underlyingError: Error? = nil) {
        self.category = category
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.underlyingError = underlyingError
    }

    /// 将通用 Error 转换为 AppError
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError { return appError }

        let nsError = error as NSError

        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
                return AppError(category: .network, message: "网络连接不可用", recoverySuggestion: "请检查网络设置或切换 Wi-Fi/蜂窝数据")
            case NSURLErrorTimedOut:
                return AppError(category: .network, message: "请求超时", recoverySuggestion: "网络不稳定，请稍后重试或切换服务器")
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                return AppError(category: .network, message: "无法连接服务器", recoverySuggestion: "请检查服务器地址是否正确，或尝试其他服务器")
            case NSURLErrorBadServerResponse:
                return AppError(category: .server, message: "服务器响应异常", recoverySuggestion: "服务器暂时不可用，请稍后重试")
            default:
                return AppError(category: .network, message: "网络错误: \(nsError.localizedDescription)", recoverySuggestion: "请检查网络连接")
            }
        case "EdgeTTSError":
            if let ttsError = error as? EdgeTTSError {
                return ttsError.asAppError
            }
            return AppError(category: .audio, message: "TTS 合成失败: \(nsError.localizedDescription)", recoverySuggestion: "请尝试更换语音或检查服务器状态")
        case "AIWorkerError":
            if let aiError = error as? AIWorkerError {
                return aiError.asAppError
            }
            return AppError(category: .parsing, message: "AI 解析失败: \(nsError.localizedDescription)", recoverySuggestion: "文本可能过长或格式异常，请尝试重新导入")
        case NSCocoaErrorDomain:
            if nsError.code == NSFileWriteOutOfSpaceError || nsError.code == NSFileWriteNoPermissionError {
                return AppError(category: .storage, message: "存储空间不足或无写入权限", recoverySuggestion: "请清理存储空间或在设置中授权文件访问")
            }
            return AppError(category: .storage, message: "文件操作失败: \(nsError.localizedDescription)", recoverySuggestion: "请重试或重启应用")
        default:
            return AppError(category: .unknown, message: error.localizedDescription, recoverySuggestion: nil)
        }
    }

    /// 统一的用户展示文本
    var userFacingMessage: String {
        if let suggestion = recoverySuggestion {
            return "\(message)\n\n建议: \(suggestion)"
        }
        return message
    }
}

// MARK: - EdgeTTSError extension
extension EdgeTTSError {
    var asAppError: AppError {
        switch self {
        case .invalidServerURL:
            return AppError(category: .validation, message: "无效的 TTS 服务器地址", recoverySuggestion: "请在设置中检查服务器 URL 格式")
        case .missingServerURL:
            return AppError(category: .validation, message: "未配置 TTS 服务器", recoverySuggestion: "请在设置中添加 Edge TTS 服务器")
        case .invalidResponse:
            return AppError(category: .server, message: "TTS 服务器响应异常", recoverySuggestion: "请检查服务器是否正常运行，或尝试其他服务器")
        case .emptyResponse:
            return AppError(category: .audio, message: "TTS 返回空音频", recoverySuggestion: "文本可能为空，请检查输入内容")
        case .networkError(let msg):
            return AppError(category: .network, message: "网络错误: \(msg)", recoverySuggestion: "请检查网络连接")
        }
    }
}

// MARK: - AIWorkerError extension
extension AIWorkerError {
    var asAppError: AppError {
        switch self {
        case .invalidURL:
            return AppError(category: .validation, message: "AI Worker 地址无效", recoverySuggestion: "请检查 Worker URL 格式，应为 https://your-worker.workers.dev")
        case .unauthorized:
            return AppError(category: .auth, message: "AI Worker 认证失败", recoverySuggestion: "请检查 Auth Key 是否正确，或在 Worker 设置中更新密钥")
        case .rateLimited:
            return AppError(category: .server, message: "AI Worker 请求过于频繁", recoverySuggestion: "请稍等片刻再试，或增加 Worker 配额")
        case .serverError(let code, let msg):
            return AppError(category: .server, message: "AI Worker 错误 (HTTP \(code))", recoverySuggestion: "服务端异常: \(msg)\n请稍后重试或联系管理员")
        case .decodingFailed(let err):
            return AppError(category: .parsing, message: "AI 返回格式解析失败", recoverySuggestion: "AI 返回数据异常: \(err.localizedDescription)\n请重试或检查 Worker 版本")
        case .timeout:
            return AppError(category: .network, message: "AI Worker 请求超时", recoverySuggestion: "网络较慢或 Worker 处理耗时过长，请增加超时时间或重试")
        case .cancelled:
            return AppError(category: .unknown, message: "请求已取消", recoverySuggestion: nil)
        }
    }
}