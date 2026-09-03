import SwiftUI
import SwiftData

// Kullanıcı DashboardView'daki fiş geçmişinden bir fişe tıkladığında
// açılan ekran. Burada o fişin tüm kalemlerini tek tek görüyor,
// isterse düzenliyor ya da siliyor.
struct ReceiptDetailView: View {

    // @Bindable sayesinde receipt.storeName gibi alanları doğrudan
    // TextField'a bağlayabiliyoruz, kullanıcı yazdıkça veritabanındaki
    // nesne de anlık güncelleniyor.
    @Bindable var receipt: Receipt
    @Environment(\.modelContext) private var modelContext

    // Kullanıcının düzenlemek için tıkladığı kalemi geçici olarak tutuyoruz,
    // bu doluysa alttan bir düzenleme ekranı (sheet) açılıyor
    @State private var editingItem: ReceiptItem?

    var body: some View {
        List {
            Section {
                // Fiş fotoğrafı kaydedilmişse (JPEG veri olarak saklanmıştı),
                // burada tekrar gösteriyoruz ki kullanıcı orijinaliyle karşılaştırabilsin
                if let data = receipt.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                }

                // Market adını buradan da düzenleyebiliyoruz
                HStack {
                    Text("Market")
                    Spacer()
                    TextField("Market adı", text: $receipt.storeName)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Tarih")
                    Spacer()
                    Text(receipt.date.formatted(date: .long, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Toplam")
                        .font(.headline)
                    Spacer()
                    // Receipt modelindeki totalAmount hesaplanan özelliği kullanıyoruz,
                    // kalemler değiştikçe bu rakam da otomatik güncelleniyor
                    Text(receipt.totalAmount.formattedAsCurrency)
                        .font(.headline)
                }
            }

            Section("Kalemler (\(receipt.items.count))") {
                // Kalemleri eklenme sırasına göre gösteriyoruz
                ForEach(receipt.items.sorted(by: { $0.createdAt < $1.createdAt })) { item in
                    ReceiptItemRow(item: item)
                        .contentShape(Rectangle())
                        // Bir satıra dokununca o kalemi düzenleme ekranını açıyoruz
                        .onTapGesture {
                            editingItem = item
                        }
                        // Satırı sağa kaydırınca "Sil" seçeneği çıkıyor
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(receipt.storeName)
        .navigationBarTitleDisplayMode(.inline)
        // editingItem doluyken bu sheet otomatik açılıyor, nil olunca kapanıyor
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
        }
    }

    // Bir kalemi hem SwiftData'dan hem de fişin kendi items dizisinden siliyoruz,
    // ikisini de yapmazsak ekranda "hayalet" bir satır kalabilir.
    private func delete(_ item: ReceiptItem) {
        modelContext.delete(item)
        receipt.items.removeAll { $0.id == item.id }
        try? modelContext.save()
    }
}

// MARK: - Kalem Satırı

// Listede tek bir ürünü (kategori emojisi, adı ve fiyatı ile) gösteren
// basit, tekrar kullanılabilir bir satır.
private struct ReceiptItemRow: View {
    let item: ReceiptItem

    var body: some View {
        HStack {
            Text(item.category.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                Text(item.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.price.formattedAsCurrency)
                .font(.subheadline.bold())
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Düzenleme Ekranı

// Bir fiş kaleminin adını, fiyatını ve kategorisini düzeltmek için açılan
// modal (alttan açılan) ekran. OCR bazen yanlış okuyabiliyor (örn. "5" yerine
// "S" okuyabilir), kullanıcı bu ekrandan hatayı elle düzeltebiliyor.
private struct EditItemSheet: View {
    @Bindable var item: ReceiptItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Fiyatı burada da metin olarak tutuyoruz (Models.swift'teki Double alanından
    // farklı olarak), çünkü kullanıcı klavyede yazarken ara ara geçersiz bir
    // değer olabilir ("24," gibi), bunu direkt Double'a çevirmeye çalışmak sorun çıkarır
    @State private var priceText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Ürün Bilgisi") {
                    TextField("Ürün adı", text: $item.name)
                    TextField("Fiyat", text: $priceText)
                        .keyboardType(.decimalPad)
                }

                Section("Kategori") {
                    // Kullanıcı otomatik atanan kategoriyi beğenmezse buradan değiştirebiliyor
                    Picker("Kategori", selection: $item.category) {
                        ForEach(ReceiptCategory.allCases) { category in
                            Label("\(category.emoji) \(category.displayName)", systemImage: "tag")
                                .tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                }

                // OCR'ın orijinal olarak ne okuduğunu da gösteriyoruz, böylece
                // kullanıcı "bu neden bu kategoriye/isme düştü" diye merak ederse
                // kaynağını görebiliyor
                if let rawText = item.rawOCRText, !rawText.isEmpty {
                    Section("Orijinal OCR Metni") {
                        Text(rawText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Kalemi Düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        // priceText'i gerçek bir Double'a çevirip modele yazıyoruz,
                        // geçersizse eski fiyatı koruyoruz (yanlışlıkla 0'a düşmesin diye)
                        item.price = Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? item.price
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
            // Ekran ilk açıldığında mevcut fiyatı metin alanına dolduruyoruz
            .onAppear {
                priceText = String(format: "%.2f", item.price)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailView(receipt: Receipt(storeName: "Örnek Market"))
    }
    .modelContainer(for: [Receipt.self, ReceiptItem.self], inMemory: true)
}
