import SwiftUI
import SwiftData
import Charts

// Kategori bazında harcamaların toplamını ve yüzdesini tutan basit bir yapı.
// Bu, veritabanı modeli değil, sadece ekranda göstermek için hesapladığımız
// geçici bir özet nesnesi.
struct CategorySummary: Identifiable {
    let id = UUID()
    let category: ReceiptCategory
    let total: Double        // Bu kategoride toplam ne kadar harcanmış
    let percentage: Double   // Genel harcamanın yüzde kaçı bu kategoriye ait
}

// Uygulamanın ikinci ana ekranı: kullanıcının şimdiye kadar kaydettiği tüm
// fişlere bakıp genel bir özet çıkarıyor, kategori bazlı grafik gösteriyor
// ve geçmiş fişlerin listesini sunuyor.
struct DashboardView: View {

    // @Query, SwiftData'ya "bana tüm Receipt'leri, tarihe göre en yeniden
    // en eskiye sıralı şekilde getir" diyor. Veritabanı her değiştiğinde
    // (yeni fiş eklendiğinde) bu liste otomatik güncelleniyor, elle
    // yenileme yapmamıza gerek kalmıyor.
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    // Kullanıcı pasta grafik mi çubuk grafik mi görmek istediğini seçebiliyor
    @State private var chartType: ChartDisplayType = .pie

    enum ChartDisplayType: String, CaseIterable, Identifiable {
        case pie = "Pasta"
        case bar = "Çubuk"
        var id: String { rawValue }
    }

    // Tüm fişlerdeki tüm ürünleri tek bir düz listede topluyoruz,
    // böylece kategori bazlı hesaplamaları kolayca yapabiliyoruz.
    private var allItems: [ReceiptItem] {
        receipts.flatMap { $0.items }
    }

    // Şimdiye kadarki toplam harcama (tüm fişler, tüm ürünler dahil)
    private var totalSpending: Double {
        allItems.reduce(0) { $0 + $1.price }
    }

    // Ürünleri kategoriye göre gruplayıp her kategori için toplam ve yüzde hesaplıyoruz.
    // En çok harcanan kategori en üstte görünsün diye büyükten küçüğe sıralıyoruz.
    private var categorySummaries: [CategorySummary] {
        // Dictionary(grouping:) ile ürünleri kategorilerine göre kutulara ayırıyoruz
        let grouped = Dictionary(grouping: allItems, by: { $0.category })
        return ReceiptCategory.allCases.compactMap { category in
            // Bu kategoride hiç ürün yoksa listede hiç göstermiyoruz (grafikte
            // boş bir dilim olmasın diye)
            guard let items = grouped[category], !items.isEmpty else { return nil }
            let total = items.reduce(0) { $0 + $1.price }
            // Yüzdeyi hesaplarken sıfıra bölme hatası olmasın diye önce kontrol ediyoruz
            let percentage = totalSpending > 0 ? (total / totalSpending) * 100 : 0
            return CategorySummary(category: category, total: total, percentage: percentage)
        }
        .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Hiç fiş yoksa boş durum ekranı, varsa gerçek içerik
                    if receipts.isEmpty {
                        emptyState
                    } else {
                        totalCard
                        chartTypePicker
                        chartSection
                        categoryList
                        receiptHistorySection
                    }
                }
                .padding()
            }
            .navigationTitle("Harcama Özeti")
            // Kullanıcı geçmiş fişlerden birine tıklayınca, o fişin detay
            // ekranına (ReceiptDetailView) yönlendiriyoruz
            .navigationDestination(for: Receipt.self) { receipt in
                ReceiptDetailView(receipt: receipt)
            }
        }
    }

    // MARK: - Bölümler

    // Kullanıcı hiç fiş taramadıysa gösterdiğimiz, yönlendirici mesajlı boş ekran
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.pie")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Henüz bir fiş taramadınız")
                .font(.headline)
            Text("İlk fişinizi tarayın, harcamalarınız burada görünsün.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
    }

    // Ekranın en üstünde büyük yazıyla toplam harcamayı gösteren kart
    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Toplam Harcama")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(totalSpending.formattedAsCurrency)
                .font(.system(size: 34, weight: .bold))
            Text("\(receipts.count) fiş • \(allItems.count) ürün")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    // Pasta/Çubuk grafik arasında geçiş yapan segment kontrolü
    private var chartTypePicker: some View {
        Picker("Grafik Türü", selection: $chartType) {
            ForEach(ChartDisplayType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
    }

    // Seçilen grafik türüne göre Swift Charts ile pasta ya da çubuk grafik çiziyoruz
    @ViewBuilder
    private var chartSection: some View {
        switch chartType {
        case .pie:
            // SectorMark = pasta grafiğin her bir dilimi. Her kategori için
            // bir dilim çiziliyor, dilimin büyüklüğü o kategorinin tutarına göre belirleniyor.
            Chart(categorySummaries) { summary in
                SectorMark(
                    angle: .value("Tutar", summary.total),
                    innerRadius: .ratio(0.55),  // Ortasını boş bırakarak "donut" görünümü veriyoruz
                    angularInset: 1.5            // Dilimler arasında ince boşluk
                )
                .foregroundStyle(by: .value("Kategori", summary.category.displayName))
                .cornerRadius(4)
            }
            .frame(height: 260)
            .chartLegend(position: .bottom, spacing: 12)

        case .bar:
            // BarMark = her kategori için yatay bir çubuk. Çubuğun uzunluğu tutara göre değişiyor.
            Chart(categorySummaries) { summary in
                BarMark(
                    x: .value("Tutar", summary.total),
                    y: .value("Kategori", summary.category.displayName)
                )
                .foregroundStyle(by: .value("Kategori", summary.category.displayName))
                .annotation(position: .trailing) {
                    // Çubuğun sağına o kategorinin tutarını yazı olarak da ekliyoruz
                    Text(summary.total.formattedAsCurrency)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // Kategori sayısına göre grafiğin yüksekliğini otomatik ayarlıyoruz,
            // az kategori varsa kısa, çok kategori varsa uzun bir grafik oluyor
            .frame(height: CGFloat(categorySummaries.count) * 50 + 40)
        }
    }

    // Grafiğin altında, her kategorinin tutarını ve yüzdesini metin olarak
    // da listeleyen bölüm (grafiği okumak zor gelirse buradan net rakamları görebiliyor)
    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kategori Dağılımı")
                .font(.headline)

            ForEach(categorySummaries) { summary in
                HStack {
                    Text(summary.category.emoji)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.category.displayName)
                            .font(.subheadline.bold())
                        Text("%\(String(format: "%.1f", summary.percentage))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(summary.total.formattedAsCurrency)
                        .font(.subheadline.bold())
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // Kullanıcının geçmişte taradığı tüm fişlerin listesi. Her satıra
    // tıklayınca o fişin detayına gidiliyor.
    private var receiptHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fiş Geçmişi")
                .font(.headline)

            ForEach(receipts) { receipt in
                // NavigationLink(value:) ile receipt nesnesinin kendisini gönderiyoruz,
                // yukarıdaki navigationDestination bunu yakalayıp doğru ekranı açıyor
                NavigationLink(value: receipt) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(receipt.storeName)
                                .font(.subheadline.bold())
                            Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(receipt.totalAmount.formattedAsCurrency)
                            .font(.subheadline.bold())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)
            }
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [Receipt.self, ReceiptItem.self], inMemory: true)
}
