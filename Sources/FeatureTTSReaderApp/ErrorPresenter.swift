import SwiftUI
import Combine

/// 全局错误呈现器：统一错误分类、本地化、用户可操作的恢复建议
@MainActor
final class ErrorPresenter: ObservableObject {
    static let shared = ErrorPresenter()

    @Published var currentError: AppError?
    @Published var isPresented = false

    private init() {}

    /// 展示错误（自动分类、本地化、附加恢复建议）
    func present(_ error: Error) {
        let appError = AppError.from(error)
        present(appError)
    }

    func present(_ appError: AppError) {
        currentError = appError
        isPresented = true
        // Log for debugging
        DebugLogger.log(flow: "error_presenter", step: "present", details: [
            "category": "\(appError.category)",
            "message": appError.message,
            "suggestion": appError.recoverySuggestion ?? "none"
        ])
    }

    func dismiss() {
        currentError = nil
        isPresented = false
    }
}

/// ViewModifier 便于在任意视图层级捕获并呈现错误
struct ErrorAlertModifier: ViewModifier {
    @EnvironmentObject var errorPresenter: ErrorPresenter

    func body(content: Content) -> some View {
        content
            .alert(
                errorPresenter.currentError?.message ?? "错误",
                isPresented: $errorPresenter.isPresented,
                presenting: errorPresenter.currentError
            ) { error in
                Button("确定") { errorPresenter.dismiss() }
                if let suggestion = error.recoverySuggestion, !suggestion.isEmpty {
                    Button("查看建议") {
                        // 可扩展：打开详情页、跳转设置页等
                        errorPresenter.dismiss()
                    }
                }
            } message: { error in
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                }
            }
    }
}

extension View {
    func withErrorAlert() -> some View {
        modifier(ErrorAlertModifier())
            .environmentObject(ErrorPresenter.shared)
    }
}

/// 带有主要/次要动作的错误弹窗（用于需要用户决策的场景，如重试/切换服务器/去设置）
struct ErrorActionAlert: ViewModifier {
    @EnvironmentObject var errorPresenter: ErrorPresenter
    let primaryAction: (() -> Void)?
    let secondaryAction: (() -> Void)?
    let primaryLabel: String
    let secondaryLabel: String

    init(
        primaryLabel: String = "重试",
        secondaryLabel: String = "设置",
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    func body(content: Content) -> some View {
        content
            .alert(
                errorPresenter.currentError?.message ?? "错误",
                isPresented: $errorPresenter.isPresented,
                presenting: errorPresenter.currentError
            ) { error in
                if let primary = primaryAction {
                    Button(primaryLabel) { primary(); errorPresenter.dismiss() }
                } else {
                    Button(primaryLabel) { errorPresenter.dismiss() }
                }
                if let secondary = secondaryAction {
                    Button(secondaryLabel) { secondary(); errorPresenter.dismiss() }
                } else if error.recoverySuggestion != nil {
                    Button("查看建议") { errorPresenter.dismiss() }
                }
                Button("取消", role: .cancel) { errorPresenter.dismiss() }
            } message: { error in
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                }
            }
    }
}

extension View {
    func withErrorActions(
        primaryLabel: String = "重试",
        secondaryLabel: String = "设置",
        primaryAction: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorActionAlert(
            primaryLabel: primaryLabel,
            secondaryLabel: secondaryLabel,
            primaryAction: primaryAction,
            secondaryAction: secondaryAction
        ))
        .environmentObject(ErrorPresenter.shared)
    }
}