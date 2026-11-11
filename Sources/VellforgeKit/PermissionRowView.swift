import SwiftUI

/// One permission, why it is wanted, and whether it is granted, with a button
/// to fix it. Shared by the welcome window and every Settings pane, so the
/// same permission is always explained the same way.
public struct PermissionRowView: View {

    let permission: Permission
    let reason: String
    let isRequired: Bool

    public init(_ use: PermissionUse) {
        self.permission = use.permission
        self.reason = use.reason
        self.isRequired = use.isRequired
    }

    public init(permission: Permission, reason: String, isRequired: Bool) {
        self.permission = permission
        self.reason = reason
        self.isRequired = isRequired
    }

    public var body: some View {
        let granted = PermissionMonitor.shared.isGranted(permission)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(permission.title).fontWeight(.medium)
                Text(isRequired ? "Required" : "Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if granted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Allow…") { permission.requestAndOpenSettings() }
                }
            }
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !granted && permission.needsRelaunchAfterGrant {
                HStack {
                    Text("macOS only applies this after Vellforge restarts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button("Relaunch Vellforge") { AppInfo.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
