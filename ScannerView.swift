import SwiftUI
import PhotosUI
import SwiftData

// Uygulamanın ana ekranlarından biri: kullanıcı burada fiş fotoğrafı çekiyor
// ya da galeriden seçiyor, OCR sonucu çıkan ürünleri görüp düzeltiyor ve
// en sonunda "Kaydet" diyerek fişi veritabanına yazdırıyor.
struct ScannerView: View {

    // SwiftData'nın veritabanı bağlamını (context) SwiftUI ortamından alıyoruz,
    // kaydetme işlemini bununla yapacağız.
    @Environment(\.modelContext) private var modelContext

    // Bütün iş mantığı ViewModel'de, bu view sadece onun durumuna göre
    // ne göstereceğine karar veriyor.
    @State private var viewModel = ReceiptScannerViewModel()

    // Kamera sayfasının açık olup olmadığını tutan basit bir bayrak (flag)
    @State private var showCamera = false

    // Kullanıcının galeriden seçtiği fotoğrafı geçici olarak tutan değişken
    @State private var photosPickerItem: PhotosPickerItem?

    // Kayıt başarılı olduğunda küçük bir onay uyarısı göstermek için kullanıyoruz
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Fotoğraf alanı + kamera/galeri butonları her zaman görünür
                    imageSection

                    // OCR çalışırken kullanıcıya "bekleniyor" göstergesi gösteriyoruz
                    if viewModel.isProcessing {
                        processingSection
                    }

                    // Bir hata varsa kullanıcıyı bilgilendiren turuncu bir bant gösteriyoruz
                    if let error = viewModel.errorMessage {
                        errorBanner(message: error)
                    }

                    // OCR'dan en az bir kalem çıktıysa, düzenleme alanlarını gösteriyoruz
                    if !viewModel.draftItems.isEmpty {
                        storeNameField
                        itemsSection
                        totalSection
                        saveButton
                    }
                }
                .padding()
            }
            .navigationTitle("Fiş Tara")
            // Kamera açık olduğunda CameraPickerView'ı tam ekran sheet olarak gösteriyoruz
            .sheet(isPresented: $showCamera) {
                CameraPickerView { image in
                    // Fotoğraf çekilir çekilmez OCR sürecini arka planda başlatıyoruz
                    Task { await viewModel.processImage(image) }
                }
                .ignoresSafeArea()
            }
            // Kullanıcı galeriden bir fotoğraf seçtiğinde bu blok tetikleniyor
            .onChange(of: photosPickerItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    // PhotosPickerItem'ı önce ham veriye (Data), sonra da UIImage'a çeviriyoruz
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await viewModel.processImage(uiImage)
                    }
                    // İşimiz bitince seçili öğeyi sıfırlıyoruz ki aynı fotoğraf
                    // tekrar seçilmek istendiğinde onChange yine tetiklensin
                    photosPickerItem = nil
                }
            }
            // Kayıt başarılı olduğunda kullanıcıya kısa bir teşekkür/onay mesajı gösteriyoruz
            .alert("Fiş Kaydedildi", isPresented: $showSaveConfirmation) {
                Button("Tamam", role: .cancel) { }
            } message: {
                Text("Fiş ve kalemleri başarıyla kaydedildi.")
            }
        }
    }

    // MARK: - Alt Bölümler
    // Ekranı okunabilir tutmak için her parçayı ayrı bir "computed property" olarak yazdık.

    // Fotoğrafın gösterildiği ya da placeholder'ın durduğu, altında da
    // Kamera/Galeri butonlarının olduğu bölüm
    private var imageSection: some View {
        VStack(spacing: 12) {
            if let image = viewModel.selectedImage {
                // Bir fotoğraf seçilmişse onu ekranda büyük gösteriyoruz
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 4)
            } else {
                // Henüz fotoğraf seçilmediyse kullanıcıyı yönlendiren boş bir kutu gösteriyoruz
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text("Bir fiş fotoğrafı çekin veya seçin")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            HStack(spacing: 12) {
                // Kamera butonu: fiziksel kamera yoksa (simülatör gibi) otomatik devre dışı kalıyor
                Button {
                    showCamera = true
                } label: {
                    Label("Kamera", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!CameraPickerView.isCameraAvailable)

                // Galeri butonu: Apple'ın hazır PhotosPicker bileşenini kullanıyoruz,
                // kendimiz UIKit köprüsü yazmamıza gerek yok
                PhotosPicker(
                    selection: $photosPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Galeri", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // OCR arka planda çalışırken gösterilen basit bir yükleniyor göstergesi
    private var processingSection: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Fiş taranıyor ve analiz ediliyor...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // Bir hata olduğunda kullanıcıya gösterilen turuncu uyarı bandı
    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    // Market adını elle girebileceğimiz basit bir metin alanı
    private var storeNameField: some View {
        HStack {
            Image(systemName: "storefront")
                .foregroundStyle(.secondary)
            TextField("Market adı", text: $viewModel.storeName)
                .textInputAutocapitalization(.words)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // OCR'dan çıkan (ya da elle eklenen) tüm ürün satırlarının listesi
    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fiş Kalemleri")
                    .font(.headline)
                Spacer()
                // Kullanıcı OCR'ın kaçırdığı bir ürünü elle eklemek isterse bu butonu kullanıyor
                Button {
                    viewModel.addEmptyItem()
                } label: {
                    Label("Ekle", systemImage: "plus.circle.fill")
                }
                .font(.subheadline)
            }

            // Her kalem için ayrı bir satır (DraftItemRow) çiziyoruz
            ForEach(viewModel.draftItems) { item in
                DraftItemRow(
                    item: binding(for: item),
                    onDelete: { viewModel.deleteItem(item) }
                )
            }
        }
    }

    // Tüm kalemlerin toplamını gösteren vurgulu kutu
    private var totalSection: some View {
        HStack {
            Text("Toplam")
                .font(.headline)
            Spacer()
            Text(viewModel.totalAmount.formattedAsCurrency)
                .font(.title3.bold())
        }
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // Kullanıcı gözden geçirmeyi bitirince fişi veritabanına kaydeden buton
    private var saveButton: some View {
        Button {
            if viewModel.saveReceipt(modelContext: modelContext) != nil {
                showSaveConfirmation = true
            }
        } label: {
            Label("Fişi Kaydet", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    // MARK: - Yardımcılar

    // ViewModel içindeki draftItems dizisinin belirli bir elemanına doğrudan
    // "Binding" (iki yönlü bağlantı) oluşturuyoruz. Bu sayede kullanıcı
    // TextField'da yazı yazınca direkt ViewModel'deki veri de güncelleniyor.
    private func binding(for item: DraftReceiptItem) -> Binding<DraftReceiptItem> {
        guard let index = viewModel.draftItems.firstIndex(where: { $0.id == item.id }) else {
            return .constant(item)
        }
        return $viewModel.draftItems[index]
    }
}

// MARK: - Tek Bir Fiş Kalemi Satırı

// Her ürün satırını (isim, fiyat, kategori) tek bir kart olarak gösteren
// küçük, tekrar kullanılabilir bir alt view.
private struct DraftItemRow: View {
    @Binding var item: DraftReceiptItem
    var onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                // Ürün adını değiştirebileceğimiz alan
                TextField("Ürün adı", text: $item.name)
                    .textInputAutocapitalization(.sentences)

                // Fiyatı değiştirebileceğimiz alan, sayısal klavye açılıyor
                TextField("Fiyat", text: $item.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            HStack {
                // Kategoriyi değiştirmek için küçük bir menü (dropdown gibi çalışıyor)
                Menu {
                    ForEach(ReceiptCategory.allCases) { category in
                        Button {
                            item.category = category
                        } label: {
                            Label("\(category.emoji) \(category.displayName)", systemImage: "tag")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(item.category.emoji)
                        Text(item.category.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Spacer()

                // Bu satırı tamamen silmek istersek kullandığımız çöp kutusu butonu
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Para Birimi Biçimlendirme

// Uygulama genelinde bir Double'ı "₺24,90" gibi düzgün bir para birimi
// yazısına çeviren yardımcı özellik. Böylece her yerde tekrar tekrar
// formatlama kodu yazmıyoruz.
extension Double {
    var formattedAsCurrency: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.currencyCode = "TRY"
        return formatter.string(from: NSNumber(value: self)) ?? "₺\(String(format: "%.2f", self))"
    }
}

#Preview {
    ScannerView()
        .modelContainer(for: [Receipt.self, ReceiptItem.self], inMemory: true)
}
