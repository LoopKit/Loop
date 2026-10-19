//
//  CriticalEventLogExportView.swift
//  Loop
//
//  Created by Darin Krauss on 7/10/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import LoopKitUI

struct CriticalEventLogExportView: View {
    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var viewModel: CriticalEventLogExportViewModel

    var body: some View {
        Group {
            Spacer()
            if !viewModel.showingSuccess {
                exportingView
            } else {
                exportedView
            }
            Spacer()
            Spacer()
        }
        .navigationBarTitle(Text("Critical Event Logs", comment: "Critical event log export title"), displayMode: .automatic)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(leading: cancelButton)
        .onAppear { self.viewModel.export() }
        .alert(isPresented: $viewModel.showingError) {
            errorAlert
        }
    }

    private var cancelButton: some View {
        Button(action: {
            self.viewModel.cancel()
            self.presentationMode.wrappedValue.dismiss()
        }) {
            Text("Cancel", comment: "Cancel export button title")
        }
    }

    private var exportingView: some View {
        VStack {
            Text("Preparing Critical Event Logs", comment: "Preparing critical event log text")
                .bold()
            ProgressView(progress: CGFloat(viewModel.progress))
                .accentColor(.loopAccent)
                .padding()
            Text(viewModel.remainingDuration ?? " ")  // Vertical alignment hack
        }
    }

    private var exportedView: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.loopAccent)
                .padding()
            Text("Critical Event Log Ready", comment: "Critical event log ready text")
                .bold()
        }
        .sheet(isPresented: $viewModel.showingShare, onDismiss: {
            self.viewModel.cancel()
            self.presentationMode.wrappedValue.dismiss()
        }) {
            ActivityViewController(activityItems: self.viewModel.activityItems, applicationActivities: nil)
        }
    }

    private var errorAlert: SwiftUI.Alert {
        Alert(title: Text("Error Exporting Logs", comment: "Critical event log export error alert title"),
              message: Text("Critical Event Logs were not able to be exported.", comment: "Critical event log export error alert message"),
              primaryButton: errorAlertPrimaryButton,
              secondaryButton: errorAlertSecondaryButton)
    }

    private var errorAlertPrimaryButton: SwiftUI.Alert.Button {
        .cancel() {
            self.viewModel.cancel()
            self.presentationMode.wrappedValue.dismiss()
        }
    }

    private var errorAlertSecondaryButton: SwiftUI.Alert.Button {
        .default(Text("Try Again", comment: "Critical event log export error alert try again button")) {
            self.viewModel.export()
        }
    }
}

fileprivate struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

public struct CriticalEventLogExportView_Previews: PreviewProvider {
    public static var previews: some View {
        let exportingViewModel = CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory())
        exportingViewModel.progress = 0.5
        exportingViewModel.remainingDuration = "About 3 minutes remaining"
        let exportedViewModel = CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory())
        exportedViewModel.showingSuccess = true
        return Group {
            CriticalEventLogExportView(viewModel: exportingViewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("Exporting - iPhone SE 2 - Light")
            CriticalEventLogExportView(viewModel: exportingViewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("Exporting - iPhone XS Max - Dark")
            CriticalEventLogExportView(viewModel: exportedViewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("Exported - iPhone SE 2 - Light")
        }
    }
}

class MockCriticalEventLogExporterFactory: CriticalEventLogExporterFactory {
    func createExporter(to url: URL) -> CriticalEventLogExporter { MockCriticalEventLogExporter() }
}

class MockCriticalEventLogExporter: CriticalEventLogExporter {
    var delegate: CriticalEventLogExporterDelegate?
    var progress: Progress = Progress.discreteProgress(totalUnitCount: 0)
    func export(now: Date, completion: @escaping (Error?) -> Void) { completion(nil) }
}
