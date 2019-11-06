//
//  CarbAbsorptionModelView.swift
//  Loop
//
//  Created by Ivan Valkou on 06.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit

struct CarbAbsorptionModelView: View {
    final class ViewModel: ObservableObject {
        @Published var model: CarbAbsorptionModel

        init(model: CarbAbsorptionModel) {
            self.model = model
        }
    }

    @ObservedObject var viewModel: ViewModel

    var body: some View {
        Form {
            Section {
                Button(action: {
                    self.viewModel.model = .linear
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Linear")
                                .foregroundColor(.primary)
                            Text("The standard linear Loop model. The initial absorption time is 1.5x (entered absorption time).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(viewModel.model == .linear ? 1 : 0)
                    }
                }

                Button(action: {
                    self.viewModel.model = .nonlinear
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nonlinear")
                                .foregroundColor(.primary)
                            Text("The same as the standard linear Loop model except the shape of the absorption curve is nonlinear. The initial absorption time is 1.5x (entered absorption time).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(viewModel.model == .nonlinear ? 1 : 0)
                    }
                }

                Button(action: {
                    self.viewModel.model = .adaptiveRateNonlinear
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adaptive Rate Nonlinear")
                                .foregroundColor(.primary)
                            Text("Uses the same model shape as the Nonlinear model, but on top of that sets the initial absorption time to be equal to the user-entered absorption time (not multiplied by 1.5).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark").opacity(viewModel.model == .adaptiveRateNonlinear ? 1 : 0)
                    }
                }

            }
        }
        .navigationBarTitle("Carb Absorption Model")
    }
}

struct CarbAbsorptionModelView_Previews: PreviewProvider {
    static var previews: some View {
        CarbAbsorptionModelView(viewModel: .init(model: .linear)).environment(\.colorScheme, .dark)
    }
}
