/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai gallery browsing client
 * Copyright (C) 2026 EhViewer Contributors
 */

import SwiftUI

struct DeviceSyncPairingView: View {
    @Binding var code: String
    let confirm: () -> Void

    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
#if os(macOS)
        macOSContent
#else
        iOSContent
#endif
    }

#if os(macOS)
    private var macOSContent: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Label("确认附近设备", systemImage: "lock.shield")
                    .font(.title2.bold())

                VStack(alignment: .leading) {
                    Text("验证码")
                        .font(.headline)
                    TextField("6 位数字验证码", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.monospacedDigit())
                        .focused($isCodeFieldFocused)
                        .onSubmit(confirmIfReady)
                        .accessibilityLabel("6 位数字验证码")
                }

                Button("确认设备", systemImage: "checkmark.shield", action: confirmIfReady)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(code.count != 6)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 560)
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task {
            isCodeFieldFocused = true
        }
        .onChange(of: code, sanitizeCode)
    }
#else
    private var iOSContent: some View {
        Form {
            Section("输入验证码") {
                TextField("6 位数字验证码", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFieldFocused)
                    .onSubmit(confirmIfReady)
                Button("确认设备", systemImage: "checkmark.shield", action: confirmIfReady)
                    .disabled(code.count != 6)
            }

        }
        .task {
            isCodeFieldFocused = true
        }
        .onChange(of: code, sanitizeCode)
    }
#endif

    private func sanitizeCode(oldValue: String, newValue: String) {
        let sanitized = String(newValue.filter(\.isNumber).prefix(6))
        if sanitized != newValue {
            code = sanitized
        }
    }

    private func confirmIfReady() {
        guard code.count == 6 else { return }
        confirm()
    }
}
