import CoreGraphics
import GoVision
import PhotosUI
import SwiftUI
#if os(iOS)
import VisionKit
#endif

/// 摆题面板最上面的导入按钮：拍作业、从相册选，还能回到上一页照片选别的题。
struct ImportControls: View {
    @Bindable var model: ProblemEditorModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // 模拟器没有摄像头，但扫描界面仍报告可用，所以在模拟器上不显示。
                #if os(iOS) && !targetEnvironment(simulator)
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        isScanning = true
                    } label: {
                        Label("拍作业", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                }
                #endif
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("从相册选", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isRecognizing)

            if model.isRecognizing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在认棋盘……").foregroundStyle(.secondary)
                }
            } else if let scanned = model.scannedPage, scanned.page.diagrams.count > 1 {
                Button {
                    model.isChoosingDiagram = true
                } label: {
                    Label("同一页选别的题", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
            }

            if model.homework != nil {
                HStack(spacing: 12) {
                    Button {
                        model.isShowingHomework = true
                    } label: {
                        Label("作业本", systemImage: "books.vertical")
                    }
                    switch model.saveState {
                    case .unsaved, .modified:
                        Button {
                            model.saveProblem()
                        } label: {
                            Label(model.saveState == .unsaved ? "保存这道题" : "保存修改", systemImage: "square.and.arrow.down")
                        }
                        .disabled(model.problem.setup.isEmpty)
                    case .saved:
                        Label("已存进作业本", systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = PhotoLoader.image(from: data) else { return }
                await model.importPhoto(image)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $isScanning) {
            DocumentScanner { image in
                Task { await model.importPhoto(image) }
            }
            .ignoresSafeArea()
        }
        #endif
    }
}

/// 校对时对照的原图。
struct ReferenceImage: View {
    let image: CGImage
    let hasUncertain: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原图").font(.headline)
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(hasUncertain
                 ? "橙色圈是没认准的地方。用“轮换”工具点一下，在黑、白、空之间切换。"
                 : "用“轮换”工具点一下，在黑、白、空之间切换。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 一页上有好几道题时，在照片上框出每道题，点哪道就导入哪道。
struct DiagramChooser: View {
    let model: ProblemEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let scanned = model.scannedPage {
                VStack(spacing: 12) {
                    if let note = scanned.note {
                        Label(note, systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    }
                    Text(summary(of: scanned.page))
                        .foregroundStyle(.secondary)
                    GeometryReader { proxy in
                        let fit = fitted(scanned.page.imageSize, in: proxy.size)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: scanned.image, scale: 1)
                                .resizable()
                                .frame(width: fit.size.width, height: fit.size.height)
                            ForEach(scanned.page.diagrams) { diagram in
                                let frame = diagram.bounds.applying(CGAffineTransform(scaleX: fit.scale, y: fit.scale))
                                Button {
                                    model.loadDiagram(diagram.id)
                                } label: {
                                    ZStack(alignment: .topLeading) {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.12))
                                            .strokeBorder(Color.accentColor, lineWidth: 3)
                                        Text(label(for: diagram))
                                            .font(.headline)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(diagram.isIncomplete ? Color.orange : Color.accentColor, in: Capsule())
                                            .foregroundStyle(.white)
                                            .padding(6)
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(width: frame.width, height: frame.height)
                                .offset(x: frame.minX, y: frame.minY)
                                .accessibilityLabel(label(for: diagram))
                            }
                        }
                        .frame(width: fit.size.width, height: fit.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding()
                .navigationTitle("选一道题")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
    }

    private func label(for diagram: RecognizedDiagram) -> String {
        let name = diagram.number.map { "第 \($0) 题" } ?? "选这道"
        return diagram.isIncomplete ? "\(name) · 没拍全" : name
    }

    private func summary(of page: RecognizedPage) -> String {
        var parts = ["找到 \(page.diagrams.count) 道题"]
        if let toPlay = page.toPlay { parts.append("\(toPlay.name)先") }
        if let goal = page.goal { parts.append(goal.name) }
        if let number = page.pageNumber { parts.append("第 \(number) 页") }
        let missing = page.missingNumbers
        if !missing.isEmpty {
            // 多半是反光、阴影或书页弯曲挡住了，重拍一张或者手动摆。
            parts.append("第 \(missing.map(String.init).joined(separator: "、")) 题没认出来，可以重拍")
        }
        return parts.joined(separator: " · ")
    }

    private func fitted(_ size: CGSize, in container: CGSize) -> (size: CGSize, scale: CGFloat) {
        let scale = min(container.width / size.width, container.height / size.height)
        return (CGSize(width: size.width * scale, height: size.height * scale), scale)
    }
}

#if os(iOS)
/// 系统的文档扫描：自动找纸的四个角、拉平，比直接拍照好认。
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (CGImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// 扫描界面只在主线程回调代理方法，所以这个遵循关系也标在主线程上。
    @MainActor
    final class Coordinator: NSObject, @MainActor VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0, let image = upright(scan.imageOfPage(at: 0)) {
                parent.onScan(image)
            }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            parent.dismiss()
        }

        /// 扫描结果带方向信息，画一遍得到方向正的图。
        private func upright(_ image: UIImage) -> CGImage? {
            if image.imageOrientation == .up { return image.cgImage }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(at: .zero)
            }.cgImage
        }
    }
}
#endif
