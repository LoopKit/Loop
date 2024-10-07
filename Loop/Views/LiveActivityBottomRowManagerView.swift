//
//  LiveActivityBottomRowManagerView.swift
//  Loop
//
//  Created by Bastiaan Verhaar on 06/07/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import LoopCore
import SwiftUI

struct LiveActivityBottomRowManagerView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    // The maximum items in the bottom row
    private let maxSize = 4
    
    @State var showAdd: Bool = false
    @State var configuration: [BottomRowConfiguration] = (UserDefaults.standard.liveActivity ?? LiveActivitySettings()).bottomRowConfiguration
    
    var addItem: ActionSheet {
        var buttons: [ActionSheet.Button] = BottomRowConfiguration.all.map { item in
            ActionSheet.Button.default(Text(item.description())) {
                configuration.append(item)
            }
        }
        buttons.append(.cancel(Text(NSLocalizedString("Cancel", comment: "Button text to cancel"))))
        
        return ActionSheet(title: Text(NSLocalizedString("Add item to bottom row", comment: "Title for Add item")), buttons: buttons)
    }
    
    var body: some View {
        List {
            ForEach($configuration, id: \.self) { item in
                HStack {
                    deleteButton
                        .onTapGesture {
                            onDelete(item.wrappedValue)
                        }
                    Text(item.wrappedValue.description())
                    
                    Spacer()
                    editBars
                }
            }
                .onMove(perform: onReorder)
                .deleteDisabled(true)
            
            Section {
                Button(action: onSave) {
                    Text(NSLocalizedString("Save", comment: ""))
                }
                .buttonStyle(ActionButtonStyle())
                .listRowInsets(EdgeInsets())
            }
        }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(
                        action: { showAdd = true },
                        label: { Image(systemName: "plus") }
                    )
                    .disabled(configuration.count >= self.maxSize)
                }
            }
            .actionSheet(isPresented: $showAdd, content: { addItem })
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Bottom row", comment: "Live activity Bottom row configuration title")))
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        ZStack {
            Color.red
                .clipShape(RoundedRectangle(cornerRadius: 12.5))
                .frame(width: 20, height: 20)
            
            Image(systemName: "minus")
                .foregroundColor(.white)
        }
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var editBars: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundColor(Color(UIColor.tertiaryLabel))
            .font(.title2)
    }
    
    private func onSave() {
        var settings = UserDefaults.standard.liveActivity ?? LiveActivitySettings()
        settings.bottomRowConfiguration = configuration
        
        UserDefaults.standard.liveActivity = settings
        NotificationCenter.default.post(name: .LiveActivitySettingsChanged, object: settings)
        
        self.presentationMode.wrappedValue.dismiss()
    }
    
    func onReorder(from: IndexSet, to: Int) {
        withAnimation {
            configuration.move(fromOffsets: from, toOffset: to)
        }
    }
    
    func onDelete(_ item: BottomRowConfiguration) {
        withAnimation {
            _ = configuration.remove(item)
        }
    }
}

#Preview {
    LiveActivityBottomRowManagerView()
}
