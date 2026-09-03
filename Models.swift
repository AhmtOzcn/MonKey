import Foundation
import SwiftData

// Bu dosya, uygulamanın "hafızasını" oluşturuyor. Yani telefonda kalıcı olarak
// saklanacak veriler burada tanımlanıyor: fişler, fişteki ürünler ve kategoriler.
// SwiftData kullanıyoruz çünkü Apple'ın kendi veritabanı çözümü, CoreData'ya göre
// çok daha az kod yazdırıyor ve doğrudan struct/class gibi davranıyor.

// MARK: - Kategori Enum

// Bir ürünün hangi harcama grubuna ait olduğunu tutan basit bir liste düşün.
// "case gida" dediğimizde aslında "Gıda" diye bir seçenek tanımlıyoruz.
// String olmasının sebebi: hem SwiftData'da kolayca saklanabilsin hem de
// ekranda direkt yazı olarak gösterebilelim.
enum ReceiptCategory: String, Codable, CaseIterable, Identifiable {
    case gida = "Gıda"
    case hijyenTemizlik = "Hijyen & Temizlik"
    case saglikMedikal = "Sağlık & Medikal"
    case tutunAlkol = "Tütün & Alkol"
    case diger = "Diğer"

    // SwiftUI'da ForEach gibi yapılarda her öğenin "kimliği" olması gerekiyor,
    // biz de kategori adının kendisini kimlik olarak kullanıyoruz.
    var id: String { rawValue }

    // Ekranda göstereceğimiz okunabilir isim (zaten rawValue ile aynı ama
    // isim ayrı bir alan olunca ileride değiştirmek istersek kolay olur)
    var displayName: String { rawValue }

    // Her kategorinin küçük bir emojisi var, listelerde ve grafiklerde
    // göze daha hoş görünmesi için kullanıyoruz.
    var emoji: String {
        switch self {
        case .gida: return "🍏"
        case .hijyenTemizlik: return "🧼"
        case .saglikMedikal: return "💊"
        case .tutunAlkol: return "🚬"
        case .diger: return "📦"
        }
    }

    // İleride grafiklerde her kategoriye sabit bir renk vermek istersek
    // diye bu ismi hazır tutuyoruz (şu an aktif olarak kullanılmıyor ama
    // Charts tarafında renk özelleştirmesi eklemek istersen işine yarar).
    var colorName: String {
        switch self {
        case .gida: return "green"
        case .hijyenTemizlik: return "blue"
        case .saglikMedikal: return "red"
        case .tutunAlkol: return "orange"
        case .diger: return "gray"
        }
    }
}

// MARK: - Fiş Kalemi

// Bir fişteki TEK BİR SATIRI temsil ediyor. Yani "Süt - 25 TL" gibi.
// @Model demek "bunu SwiftData'da tablo gibi sakla" demek.
@Model
final class ReceiptItem {
    var id: UUID
    var name: String        // Ürün adı, örn: "Tam Yağlı Süt"
    var price: Double        // Fiyatı, örn: 24.90
    var category: ReceiptCategory  // Hangi kategoriye ait olduğu
    var rawOCRText: String?  // OCR'ın satırdan okuduğu ham metin (hata ayıklamak için saklıyoruz)
    var createdAt: Date

    // Bu kalemin hangi fişe ait olduğunu tutan ters bağlantı.
    // Receipt sınıfındaki @Relationship üzerinden otomatik dolduruluyor.
    var receipt: Receipt?

    init(
        id: UUID = UUID(),
        name: String,
        price: Double,
        category: ReceiptCategory,
        rawOCRText: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.category = category
        self.rawOCRText = rawOCRText
        self.createdAt = createdAt
    }
}

// MARK: - Fiş

// Bir alışveriş fişinin tamamını temsil ediyor: hangi markette, ne zaman
// alışveriş yapıldığı ve o fişteki tüm ürünler (items).
@Model
final class Receipt {
    var id: UUID
    var storeName: String   // Market adı, örn: "Migros"
    var date: Date          // Fişin tarihi
    var imageData: Data?    // Çekilen fiş fotoğrafını da saklıyoruz (detay ekranında göstermek için)

    // Bir fişin birden fazla ürünü olabilir. deleteRule: .cascade demek:
    // "bu fişi silersen, içindeki ürünleri de otomatik sil" demek.
    // Yani elde kalan yetim veri olmasın diye bu ayarı yapıyoruz.
    @Relationship(deleteRule: .cascade, inverse: \ReceiptItem.receipt)
    var items: [ReceiptItem] = []

    init(
        id: UUID = UUID(),
        storeName: String = "Bilinmeyen Market",
        date: Date = .now,
        imageData: Data? = nil,
        items: [ReceiptItem] = []
    ) {
        self.id = id
        self.storeName = storeName
        self.date = date
        self.imageData = imageData
        self.items = items
    }

    // Fişteki tüm ürünlerin fiyatlarını toplayıp genel toplamı hesaplıyoruz.
    // Böylece "toplam tutar" diye ayrı bir alan tutmaya gerek kalmıyor,
    // her zaman güncel ve doğru sonucu buradan alıyoruz.
    var totalAmount: Double {
        items.reduce(0) { $0 + $1.price }
    }

    // Belirli bir kategoriye ait ürünlerin toplamını hesaplar.
    // Örneğin sadece "Gıda" kategorisinde ne kadar harcandığını öğrenmek için kullanılıyor.
    func totalAmount(for category: ReceiptCategory) -> Double {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.price }
    }
}
