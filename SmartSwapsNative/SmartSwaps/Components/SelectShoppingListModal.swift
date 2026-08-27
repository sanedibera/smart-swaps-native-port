import SwiftUI
import SmartSwapsKit

/// Port of `components/SelectShoppingListModal.tsx` (201 ln). `useInventory()` ->
/// `InventoryStore` via `@EnvironmentObject`. Presented via `.sheet`/`.overlay` by the
/// caller, same pattern as `SearchModal.swift`.
struct SelectShoppingListModal: View {
    var onSelect: (String?, String?) -> Void
    var onClose: () -> Void

    @EnvironmentObject private var inventory: InventoryStore
    @State private var isCreatingNew = false
    @State private var newListName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Add to Shopping List").font(.system(size: 20, weight: .heavy)).foregroundColor(Colors.textPrimary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 24)).foregroundColor(Colors.textSecondary)
                    }.buttonStyle(.plain)
                }

                if isCreatingNew {
                    newListForm
                } else {
                    listPicker
                }
            }
            .padding(24)
            .background(Colors.white)
            .cornerRadius(24)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.8)
            .padding(20)
        }
    }

    private var newListForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New List Name").font(.system(size: 13, weight: .bold)).foregroundColor(Colors.textSecondary)
            TextField("e.g. Weekend Groceries", text: $newListName)
                .focused($nameFieldFocused)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Colors.inputBackground).cornerRadius(12)
                .onAppear { nameFieldFocused = true }

            HStack(spacing: 12) {
                Button(action: { isCreatingNew = false }) {
                    Text("Cancel").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Colors.inputBackground).cornerRadius(12)
                }.buttonStyle(.plain)

                let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
                Button(action: {
                    guard !trimmed.isEmpty else { return }
                    onSelect(nil, trimmed)
                    newListName = ""
                    isCreatingNew = false
                }) {
                    Text("Create & Add").font(.system(size: 15, weight: .bold)).foregroundColor(Colors.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Colors.primaryGreen).cornerRadius(12)
                        .opacity(trimmed.isEmpty ? 0.5 : 1)
                }.buttonStyle(.plain).disabled(trimmed.isEmpty)
            }
            .padding(.top, 16)
        }
        .padding(.top, 20)
    }

    private var listPicker: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button(action: { isCreatingNew = true }) {
                    HStack {
                        Circle().fill(Colors.lightGreenBg).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "plus").font(.system(size: 20)).foregroundColor(Colors.primaryGreen))
                        Text("Create New List").font(.system(size: 16, weight: .bold)).foregroundColor(Colors.primaryGreen)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .overlay(Rectangle().fill(Colors.border).frame(height: 1), alignment: .bottom)
                }.buttonStyle(.plain)

                ForEach(inventory.shoppingLists) { list in
                    Button(action: { onSelect(list.id, nil) }) {
                        HStack {
                            Circle().fill(Color(hex: 0xF0FAFF)).frame(width: 40, height: 40)
                                .overlay(Image(systemName: "basket").font(.system(size: 20)).foregroundColor(Color(hex: 0x0084C9)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.recipeName?.isEmpty == false ? list.recipeName! : "Shopping List")
                                    .font(.system(size: 16, weight: .bold)).foregroundColor(Colors.textPrimary)
                                Text("\(list.items.count) items").font(.system(size: 13)).foregroundColor(Colors.textSecondary)
                            }
                            .padding(.leading, 12)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14)).foregroundColor(Colors.textMuted)
                        }
                        .padding(.vertical, 14)
                        .overlay(Rectangle().fill(Colors.border).frame(height: 1), alignment: .bottom)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 20)
    }
}

#Preview {
    SelectShoppingListModal(onSelect: { _, _ in }, onClose: {})
        .environmentObject(InventoryStore())
}
