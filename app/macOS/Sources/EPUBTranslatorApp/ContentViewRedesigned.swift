import AppKit
import SwiftUI

extension Notification.Name {
    static let showTranslationPage = Notification.Name("showTranslationPage")
    static let showAPIManagerPage = Notification.Name("showAPIManagerPage")
}

private enum AppPage: Hashable {
    case translation
    case apiManager
    case help

    var lineworkVariant: Int {
        switch self {
        case .translation: return 0
        case .apiManager: return 1
        case .help: return 2
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppViewModel()
    @State private var page = AppPage.translation
    @State private var providerPendingDeletion: ProviderID?
    @State private var showsDeleteConfirmation = false
    @State private var showsErrorDetails = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch page {
            case .translation:
                translationPage
            case .apiManager:
                apiManagerPage
            case .help:
                helpPage
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppColors.slate)
        .frame(minWidth: 780, idealWidth: 1120, minHeight: 600, idealHeight: 760)
        .onAppear { prepareWindowForUITestingIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .showTranslationPage)) { _ in page = .translation }
        .onReceive(NotificationCenter.default.publisher(for: .showAPIManagerPage)) { _ in page = .apiManager }
    }

    private func prepareWindowForUITestingIfNeeded() {
        #if DEBUG
        guard CommandLine.arguments.contains("--ui-testing") else { return }
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.collectionBehavior.insert(.canJoinAllSpaces)
                window.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            HStack(spacing: 11) {
                Image(systemName: "book.closed")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppColors.terracotta)
                    .accessibilityHidden(true)
                Text("EPUB翻译")
                    .font(AppTypography.brand)
                    .foregroundStyle(AppColors.primaryText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)

            Divider().overlay(AppColors.border)

            VStack(spacing: AppSpacing.small) {
                Button { page = .translation } label: {
                    Label("翻译", systemImage: "book.pages")
                }
                .buttonStyle(AppSidebarButtonStyle(isSelected: page == .translation))
                .accessibilityIdentifier("sidebarTranslation")

                Button { page = .apiManager } label: {
                    Label("API 管理", systemImage: "key")
                }
                .buttonStyle(AppSidebarButtonStyle(isSelected: page == .apiManager))
                .accessibilityIdentifier("sidebarAPIManager")

                Button { page = .help } label: {
                    Label("关于与帮助", systemImage: "questionmark.circle")
                }
                .buttonStyle(AppSidebarButtonStyle(isSelected: page == .help))
                .accessibilityIdentifier("sidebarHelp")
            }
            .padding(.horizontal, 10)
            Spacer(minLength: 20)
        }
        .frame(minWidth: 205, idealWidth: 218, maxWidth: 228, maxHeight: .infinity)
        .background(AppColors.sidebar)
    }

    private var translationPage: some View {
        pageSurface(variant: AppPage.translation.lineworkVariant) {
            PageHeader(
                title: "EPUB翻译",
                subtitle: "免费的 macOS EPUB 英译中工具",
                accessibilityIdentifier: "appTitle"
            )
            bookCard
            translationSettingsCard
            translationAction
            translationProgressPanel

            if let error = model.activeError { userFacingErrorCard(error) }
            if model.preparedTranslatedEPUBURL != nil, !model.isTranslating { translatedOutputCard }

            if let preview = model.translatedTextPreview {
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    AppSectionHeading(title: "最近完成的译文", icon: "text.quote")
                    Text(preview)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("translatedTextPreview")
                }
                .padding(20)
                .appCard()
            }

            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                AppSectionHeading(title: "状态", icon: "circle.dotted")
                Text(model.statusMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityIdentifier("statusMessage")
                    .accessibilityValue(model.statusMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .appCard()
        }
        .navigationTitle("翻译")
    }

    private var bookCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            AppSectionHeading(title: "书籍", icon: "book.closed")
            HStack(spacing: AppSpacing.regular) {
                Button { model.chooseEPUB() } label: {
                    Label("选择 EPUB…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(model.isTranslating)
                .accessibilityIdentifier("chooseEPUBButton")

                if let info = model.selectedFileInfo {
                    Text(info.fileName)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("selectedFileName")
                } else if model.isAnalyzingBook {
                    ProgressView().controlSize(.small)
                    Text("正在读取书籍…").font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                } else {
                    Text("尚未选择 EPUB").font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                }
                Spacer(minLength: 0)
            }

            if let info = model.selectedFileInfo {
                Divider().overlay(AppColors.border)
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    if let title = info.bookTitle {
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.medium) {
                            Text("书名")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                            Text(title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColors.primaryText)
                                .lineLimit(2)
                        }
                    }
                    HStack(spacing: AppSpacing.large) {
                        Label("\(info.readingDocumentCount) 个正文文件", systemImage: "doc.text")
                        Label("\(info.translationUnitCount) 个翻译单元", systemImage: "square.stack.3d.up")
                            .accessibilityIdentifier("bookUnitSummary")
                    }
                    .font(.callout)
                    .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(20)
        .appCard(strong: true)
    }

    private var translationSettingsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            AppSectionHeading(title: "翻译设置", icon: "slider.horizontal.3")
            HStack(spacing: AppSpacing.regular) {
                Text("云端 AI")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 72, alignment: .leading)
                Picker("云端 AI", selection: $model.selectedProvider) {
                    ForEach(ProviderID.allCases) { provider in Text(provider.rawValue).tag(provider) }
                }
                .labelsHidden()
                .frame(width: 220)
                .disabled(model.isTranslating)
                .accessibilityIdentifier("providerPicker")
                Spacer(minLength: 8)
                Button("API 管理") { page = .apiManager }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .accessibilityIdentifier("openAPIManagerButton")
            }

            if !model.isCredentialConfigured(for: model.selectedProvider) {
                Label(
                    "尚未添加 \(model.selectedProvider.rawValue)，请先到 API 管理粘贴 API Key。",
                    systemImage: "exclamationmark.circle"
                )
                .font(.callout)
                .foregroundStyle(AppColors.warning)
            }

            HStack(spacing: AppSpacing.regular) {
                Text("翻译为")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(width: 72, alignment: .leading)
                Text("简体中文")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.primaryText)
            }

            Divider().overlay(AppColors.border)
            VStack(alignment: .leading, spacing: AppSpacing.medium) {
                Text("翻译模式").font(AppTypography.cardTitle).foregroundStyle(AppColors.primaryText)
                Picker("翻译模式", selection: $model.selectedStyle) {
                    ForEach(TranslationStyle.allCases) { style in
                        Text(TranslationStylePromptRegistry.profile(for: style).displayName).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .disabled(model.isTranslating)
                .accessibilityIdentifier("translationStylePicker")
            }
        }
        .padding(20)
        .appCard()
    }

    @ViewBuilder
    private var translationAction: some View {
        if model.isTranslating {
            Button { model.cancelTranslation() } label: {
                Label("停止翻译", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle())
            .frame(maxWidth: 330)
            .accessibilityIdentifier("stopTranslationButton")
        } else {
            Button { model.startTranslation() } label: {
                Label(
                    model.canResumeTranslation ? "继续翻译" : "开始翻译",
                    systemImage: model.canResumeTranslation ? "arrow.clockwise" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .frame(maxWidth: 330)
            .disabled(model.isAnalyzingBook)
            .accessibilityIdentifier("startTranslationButton")
        }
    }

    private var translationProgressPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            HStack {
                AppSectionHeading(title: "翻译进度", icon: "chart.bar.xaxis")
                Spacer()
                Text("\(model.translationPercentage)%")
                    .monospacedDigit()
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .accessibilityIdentifier("translationPercentage")
            }
            Text(model.progressTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
            ProgressView(value: model.translationProgress, total: 1)
                .progressViewStyle(.linear)
                .tint(AppColors.slate)
                .accessibilityIdentifier("translationProgressBar")
                .accessibilityValue("\(model.translationPercentage)%")
            HStack {
                Text("\(model.completedTranslationUnits) / \(model.totalTranslationUnits) 个翻译单元")
                    .monospacedDigit()
                    .accessibilityIdentifier("translationUnitProgress")
                Spacer()
                Label("预计总用时 \(model.estimatedTranslationTime)", systemImage: "clock")
                    .accessibilityIdentifier("estimatedTranslationTime")
            }
            .font(.callout)
            .foregroundStyle(AppColors.secondaryText)
            Text("预计时间根据正文单元数量、字符数和所选云端 AI 计算，实际时间会受网络与服务响应速度影响。")
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText.opacity(0.78))
        }
        .padding(20)
        .appCard()
    }

    private var translatedOutputCard: some View {
        HStack(spacing: AppSpacing.regular) {
            Label(
                model.savedTranslatedEPUBURL == nil ? "译本已生成，等待保存" : "译本已保存",
                systemImage: model.savedTranslatedEPUBURL == nil ? "doc.badge.clock" : "checkmark.circle"
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(model.savedTranslatedEPUBURL == nil ? AppColors.warning : AppColors.success)
            Spacer()
            Button("保存译本…") { model.saveTranslatedEPUB() }
                .buttonStyle(AppPrimaryButtonStyle())
                .disabled(model.isSavingOutput)
                .accessibilityIdentifier("saveTranslatedEPUBButton")
            if model.savedTranslatedEPUBURL != nil {
                Button("在 Finder 中显示") { model.revealSavedTranslatedEPUB() }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .accessibilityIdentifier("revealTranslatedEPUBButton")
            }
            if model.isSavingOutput { ProgressView().controlSize(.small) }
        }
        .padding(20)
        .appCard(tint: AppColors.success)
    }

    private var apiManagerPage: some View {
        pageSurface(variant: AppPage.apiManager.lineworkVariant) {
            PageHeader(
                title: "API 管理",
                subtitle: "选择 Qwen 或 DeepSeek，只需粘贴 API Key。模型、接口地址和调用格式均由 App 自动处理。",
                accessibilityIdentifier: "apiManagerTitle"
            )
            apiEntryCard
            providerStatusCard

            HStack(alignment: .top, spacing: AppSpacing.medium) {
                Image(systemName: "info.circle").foregroundStyle(AppColors.slate).accessibilityHidden(true)
                Text(model.apiManagerMessage)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityIdentifier("apiManagerStatus")
                    .accessibilityValue(model.apiManagerMessage)
                Spacer(minLength: 0)
            }
            .padding(18)
            .appCard(tint: AppColors.slate)

            if let error = model.activeError { userFacingErrorCard(error) }
            Button("返回翻译") { page = .translation }
                .buttonStyle(AppSecondaryButtonStyle())
                .accessibilityIdentifier("backToTranslationButton")
        }
        .navigationTitle("API 管理")
        .confirmationDialog(
            "确认删除 API Key？",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if let provider = providerPendingDeletion {
                Button("删除 \(provider.rawValue) API Key", role: .destructive) {
                    model.deleteCredential(for: provider)
                    providerPendingDeletion = nil
                }
            }
            Button("取消", role: .cancel) { providerPendingDeletion = nil }
        } message: {
            if let provider = providerPendingDeletion {
                Text("将从本次运行中删除 \(provider.rawValue) 的 API Key。此操作不会影响其他服务商。")
            }
        }
    }

    private var apiEntryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            AppSectionHeading(title: "添加或更换 API Key", icon: "key.horizontal")
            VStack(alignment: .leading, spacing: 7) {
                Text("服务商").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.secondaryText)
                Picker("服务商", selection: $model.apiEntryProvider) {
                    ForEach(ProviderID.allCases) { provider in Text(provider.rawValue).tag(provider) }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                .disabled(model.providerBusy)
                .accessibilityIdentifier("apiProviderPicker")
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("API 密钥").font(.system(size: 13, weight: .semibold)).foregroundStyle(AppColors.secondaryText)
                SecureField("输入 API Key", text: $model.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .onSubmit { model.validateAndSaveEnteredAPI() }
                    .accessibilityIdentifier("apiKeySecureField")
            }
            Text("验证通过后，API Key 仅保留在本次运行的内存中，关闭 App 后自动清除；App 不会读取或写入 macOS 钥匙串。")
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText)
            HStack(spacing: AppSpacing.medium) {
                Button("验证并保存") { model.validateAndSaveEnteredAPI() }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .disabled(model.providerBusy)
                    .accessibilityIdentifier("saveAPIButton")
                Button("清空") { model.cancelCredentialEntry() }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(model.providerBusy)
                    .accessibilityIdentifier("clearAPIFormButton")
                if model.providerBusy {
                    Button("取消验证") { model.cancelCredentialValidation() }
                        .buttonStyle(AppSecondaryButtonStyle())
                        .accessibilityIdentifier("cancelCredentialValidationButton")
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(20)
        .appCard(strong: true)
    }

    private var providerStatusCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.regular) {
            AppSectionHeading(title: "API 状态", icon: "waveform.path.ecg")
            VStack(spacing: 0) {
                ForEach(Array(ProviderID.allCases.enumerated()), id: \.element.id) { index, provider in
                    savedProviderRow(provider)
                    if index < ProviderID.allCases.count - 1 { Divider().overlay(AppColors.border) }
                }
            }
        }
        .padding(20)
        .appCard()
    }

    private var helpPage: some View {
        pageSurface(variant: AppPage.help.lineworkVariant) {
            PageHeader(title: "关于与帮助", subtitle: "", accessibilityIdentifier: "helpTitle")
            HStack(alignment: .center, spacing: AppSpacing.xLarge) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 132, height: 132)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.medium) {
                    Text("EPUB翻译").font(AppTypography.heroTitle).foregroundStyle(AppColors.primaryText)
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.slate)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.slateWash, in: RoundedRectangle(cornerRadius: 7))
                    Text("免费的 macOS EPUB 英译中工具")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .appCard(strong: true)

            VStack(alignment: .leading, spacing: AppSpacing.regular) {
                AppSectionHeading(title: "遇到问题？", icon: "questionmark.circle")
                Text("你可以先复制错误卡中的脱敏诊断信息，再主动打开 GitHub Issues 反馈。App 不会自动上传日志、电子书或 API Key。")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("反馈问题…") { model.openFeedback() }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .accessibilityIdentifier("helpFeedbackButton")
                Text("反馈时请勿公开 API Key、私人 EPUB、完整文件路径或其他敏感信息。")
                    .font(.caption)
                    .foregroundStyle(AppColors.secondaryText.opacity(0.82))
            }
            .padding(22)
            .appCard()
        }
        .navigationTitle("关于与帮助")
    }

    private func userFacingErrorCard(_ error: UserFacingError) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Label(error.title, systemImage: errorIcon(error.severity))
                .font(AppTypography.cardTitle)
                .foregroundStyle(errorColor(error.severity))
                .accessibilityIdentifier("userErrorTitle")
            Text(error.message).font(AppTypography.body).foregroundStyle(AppColors.primaryText)
                .accessibilityIdentifier("userErrorMessage")
            Text(error.recoveryHint).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                .accessibilityIdentifier("userErrorRecoveryHint")
            if error.context.totalUnits > 0 {
                Text("已完成 \(error.context.completedUnits) / \(error.context.totalUnits) 个文本块")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityIdentifier("userErrorProgress")
            }
            HStack(spacing: AppSpacing.medium) {
                Button(error.primaryAction.title) { model.performErrorAction(error.primaryAction) }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .accessibilityIdentifier("userErrorPrimaryAction")
                if let secondary = error.secondaryAction {
                    Button(secondary.title) { model.performErrorAction(secondary) }
                        .buttonStyle(AppSecondaryButtonStyle())
                        .accessibilityIdentifier("userErrorSecondaryAction")
                }
                Spacer()
            }
            Button { showsErrorDetails.toggle() } label: {
                Label(
                    showsErrorDetails ? "收起详细信息" : "查看详细信息",
                    systemImage: showsErrorDetails ? "chevron.down" : "chevron.right"
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.secondaryText)
            .accessibilityIdentifier("errorDetailsButton")
            .accessibilityValue(showsErrorDetails ? "已展开" : "已收起")
            if showsErrorDetails {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    LabeledContent("错误代码") { Text(error.code) }
                    LabeledContent("阶段") { Text(error.context.stage) }
                    LabeledContent("重试次数") { Text("\(error.context.retryCount)") }
                    if let provider = error.context.provider { LabeledContent("AI 服务") { Text(provider.rawValue) } }
                    Text(error.technicalDetails).font(.caption.monospaced()).foregroundStyle(AppColors.secondaryText)
                    HStack(spacing: AppSpacing.medium) {
                        Button("复制诊断信息") { model.copyActiveErrorDiagnostics() }
                            .buttonStyle(AppSecondaryButtonStyle())
                            .accessibilityIdentifier("copyDiagnosticsButton")
                        Button("反馈问题") { model.openFeedback() }
                            .buttonStyle(AppSecondaryButtonStyle())
                            .accessibilityIdentifier("errorFeedbackButton")
                    }
                }
                .padding(.top, AppSpacing.small)
            }
        }
        .padding(20)
        .appCard(tint: errorColor(error.severity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("错误：\(error.title)。\(error.message)。\(error.recoveryHint)")
    }

    private func errorColor(_ severity: UserFacingErrorSeverity) -> Color {
        switch severity {
        case .notice: return AppColors.slate
        case .actionRequired: return AppColors.warning
        case .blocking: return AppColors.error
        }
    }

    private func errorIcon(_ severity: UserFacingErrorSeverity) -> String {
        switch severity {
        case .notice: return "info.circle"
        case .actionRequired: return "exclamationmark.circle"
        case .blocking: return "xmark.octagon"
        }
    }

    private func savedProviderRow(_ provider: ProviderID) -> some View {
        let isValidatingThisProvider = model.providerBusy && model.validatingProvider == provider
        return HStack(spacing: AppSpacing.regular) {
            Circle()
                .fill(model.hasStoredCredential(for: provider) ? AppColors.success : AppColors.secondaryText.opacity(0.35))
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(provider.rawValue).font(AppTypography.cardTitle).foregroundStyle(AppColors.primaryText)
                Text(model.credentialState(for: provider).label)
                    .font(.callout)
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityIdentifier("credentialState-\(provider.rawValue)")
                    .accessibilityValue(model.credentialState(for: provider).label)
                if model.credentialPersistence(for: provider) != nil {
                    Text("仅本次使用")
                        .font(.caption)
                        .foregroundStyle(AppColors.secondaryText.opacity(0.78))
                        .accessibilityIdentifier("credentialPersistence-\(provider.rawValue)")
                }
            }
            Spacer(minLength: AppSpacing.medium)
            if model.hasStoredCredential(for: provider) {
                Button(isValidatingThisProvider ? "取消验证" : "重新验证") {
                    if isValidatingThisProvider {
                        model.cancelCredentialValidation()
                    } else {
                        model.validateCredential(for: provider)
                    }
                }
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(model.providerBusy && !isValidatingThisProvider)
                .accessibilityIdentifier("validateCredential-\(provider.rawValue)")
                Button("更换 API Key") { model.beginCredentialEntry(for: provider) }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(model.providerBusy)
                    .accessibilityIdentifier("editCredential-\(provider.rawValue)")
                Button("删除", role: .destructive) {
                    providerPendingDeletion = provider
                    showsDeleteConfirmation = true
                }
                .buttonStyle(AppSecondaryButtonStyle())
                .disabled(model.providerBusy)
                .accessibilityIdentifier("deleteCredential-\(provider.rawValue)")
            } else {
                Button("添加 API Key") { model.beginCredentialEntry(for: provider) }
                    .buttonStyle(AppSecondaryButtonStyle())
                    .disabled(model.providerBusy)
                    .accessibilityIdentifier("editCredential-\(provider.rawValue)")
            }
        }
        .padding(.vertical, 12)
    }

    private func pageSurface<Content: View>(variant: Int, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            AppColors.canvas.ignoresSafeArea()
            ArchitecturalLineworkBackground(variant: variant)
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) { content() }
                    .frame(maxWidth: 960, alignment: .leading)
                    .padding(.horizontal, AppSpacing.page)
                    .padding(.top, AppSpacing.xLarge)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.visible)
        }
    }
}
