//
// Copyright © 2025 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import SwiftUI

/// Grouped + Text hybrid view for QEMU arguments.
/// Top: collapsible sections per category (read-only reference).
/// Bottom: editable text area for custom arguments.
@available(iOS 15, macOS 12, *)
struct VMConfigQEMUArgumentsGroupedView: View {
    @Binding var config: UTMQemuConfigurationQEMU
    let architecture: QEMUArchitecture
    let argumentGroups: [QEMUArgumentGroup]

    @State private var customArgsText: String = ""
    @State private var showExportArgs: Bool = false
    @State private var collapsedGroups: Set<String> = []

    private var exportShareItem: VMShareItemModifier.ShareItem {
        var argString = "qemu-system-\(architecture.rawValue)"
        for group in argumentGroups {
            for arg in group.arguments {
                if arg.string.contains(" ") {
                    argString += " \"\(arg.string)\""
                } else {
                    argString += " \(arg.string)"
                }
            }
        }
        for arg in config.additionalArguments {
            argString += " \(arg.string)"
        }
        return .qemuCommand(argString)
    }

    var body: some View {
        Form {
            Section {
                Button("Export QEMU Command…") {
                    showExportArgs.toggle()
                }
            }
            Section(header: Text("Generated Arguments")) {
                ForEach(argumentGroups) { group in
                    DisclosureGroup(isExpanded: groupExpandBinding(for: group.id)) {
                        Text(group.formattedArguments)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            #if os(macOS)
                            .padding(.leading, 8)
                            .textSelection(.enabled)
                            #endif
                    } label: {
                        Label {
                            HStack {
                                Text(group.name)
                                Spacer()
                                Text("\(group.arguments.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: group.icon)
                        }
                    }
                }
            }
            Section {
                if #available(iOS 16, macOS 13, *) {
                    TextEditor(text: $customArgsText)
                        .font(.system(.caption, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        #if os(macOS)
                        .frame(minHeight: 80)
                        #endif
                        .onChange(of: customArgsText) { newValue in
                            syncTextToConfig(newValue)
                        }
                } else {
                    TextEditor(text: $customArgsText)
                        .font(.system(.caption, design: .monospaced))
                        #if os(macOS)
                        .frame(minHeight: 80)
                        #endif
                        .onChange(of: customArgsText) { newValue in
                            syncTextToConfig(newValue)
                        }
                }
            } header: {
                Text("Custom Arguments")
            } footer: {
                Text("One argument per line. Each line is passed as a separate argument to QEMU.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            syncConfigToText()
        }
        .modifier(VMShareItemModifier(isPresented: $showExportArgs, shareItem: exportShareItem))
    }

    private func groupExpandBinding(for id: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { !collapsedGroups.contains(id) },
            set: { expanded in
                if expanded {
                    collapsedGroups.remove(id)
                } else {
                    collapsedGroups.insert(id)
                }
            }
        )
    }

    private func syncConfigToText() {
        customArgsText = config.additionalArguments.map(\.string).joined(separator: "\n")
    }

    private func syncTextToConfig(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        let newArgs = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { QEMUArgument($0.trimmingCharacters(in: .whitespaces)) }
        if newArgs.map(\.string) != config.additionalArguments.map(\.string) {
            config.additionalArguments = newArgs
        }
    }
}
