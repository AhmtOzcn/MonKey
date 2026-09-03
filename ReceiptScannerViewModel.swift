import Foundation
import UIKit
import SwiftData
import Observation

// Bu dosya MVVM mimarisindeki "ViewModel" katmanı. Yani ScannerView (ekran)
// ile OCRService/CategorizationService (arka plan işleri) arasındaki köprü.
// Ekran hiçbir zaman doğrudan Vision veya kategorizasyon mantığıyla uğraşmıyor,
// hep bu ViewModel üzerinden konuşuyor. Bu sayede ekran sadece "ne göstereceğine"
// odaklanıyor, iş mantığı burada, ayrı bir yerde duruyor.

// Kullanıcının tarama ekranında düzenleyebileceği, henüz kaydedilmemiş
// (yani veritabanına yazılmamış) geçici bir fiş kalemi. SwiftData modelinden
// (ReceiptItem) farklı olarak bunun fiyatı "String" tutuyoruz çünkü kullanıcı
// TextField'da yazarken "24," gibi yarım bir değer de girebilir, bunu her
// tuşta Double'a çevirmeye çalışmak sorun çıkarabilir.
struct DraftReceiptItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var priceText: String      // Kullanıcının TextField'da gördüğü metin hali
    var category: ReceiptCategory
    var rawOCRText: String     // Bu satırı Vision aslen nasıl okumuştu, referans olarak saklıyoruz

    // priceText'i gerçek bir sayıya çeviren hesaplanan özellik.
    // Kullanıcı virgülle yazabildiği için önce noktaya çeviriyoruz.
    var price: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}

// Ekranın o an hangi durumda olduğunu tutuyoruz. Bu sayede View tarafında
// "if isLoading, if hasError" gibi karışık if'ler yerine tek bir state'e
// bakıp duruma göre ne göstereceğimize karar veriyoruz.
enum ScannerViewState: Equatable {
    case idle          // Henüz bir şey yapılmadı, boş ekran
    case processing    // OCR şu an çalışıyor, kullanıcı bekliyor
    case reviewing     // OCR bitti, kullanıcı sonuçları gözden geçiriyor
    case error(String) // Bir şeyler ters gitti, mesajı burada tutuyoruz
}

// @Observable makrosu sayesinde bu sınıftaki değişen her alan otomatik olarak
// SwiftUI ekranını günceller. Yani "published" gibi ekstra bir şey yazmamıza
// gerek kalmıyor, sadece "var" ile tanımlamak yeterli.
@Observable
final class ReceiptScannerViewModel {

    // MARK: - Bağımlılıklar

    // OCR ve kategorizasyon servislerini burada tutuyoruz. Varsayılan olarak
    // gerçek servisleri kullanıyor ama testler için farklı bir servis
    // enjekte edilebilsin diye init'te parametre olarak da alabiliyoruz.
    private let ocrService: OCRService
    private let categorizationService: CategorizationService

    // MARK: - State (Ekranın o anki durumu)

    var state: ScannerViewState = .idle
    var selectedImage: UIImage?          // Kullanıcının çektiği/seçtiği fiş fotoğrafı
    var draftItems: [DraftReceiptItem] = []  // OCR'dan çıkan, henüz kaydedilmemiş kalemler
    var storeName: String = "Bilinmeyen Market"

    // Ekranda "yükleniyor" göstergesi çizip çizmeyeceğimize karar vermek için
    // kullanılan basit bir yardımcı özellik.
    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    // Eğer state şu an hata durumundaysa, hata mesajını buradan çekiyoruz.
    // Değilse nil dönüyor, yani ekranda hata bandı gösterilmiyor.
    var errorMessage: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    // Şu ana kadar eklenen tüm kalemlerin toplam tutarı.
    // Ekranda "Toplam: 145,90 TL" gibi bir yer için kullanılıyor.
    var totalAmount: Double {
        draftItems.reduce(0) { $0 + $1.price }
    }

    init(
        ocrService: OCRService = OCRService(),
        categorizationService: CategorizationService = CategorizationService()
    ) {
        self.ocrService = ocrService
        self.categorizationService = categorizationService
    }

    // MARK: - Fotoğraf İşleme

    // Kullanıcı kameradan çektiği ya da galeriden seçtiği fotoğrafı bu fonksiyona
    // verdiğinde tüm OCR + kategorizasyon akışı burada başlıyor.
    // @MainActor demek: bu fonksiyon içindeki ekran güncellemeleri (state değişimi)
    // ana thread'de (yani kullanıcı arayüzünün çalıştığı yerde) yapılsın, yoksa
    // arka plan thread'inden ekranı güncellemeye çalışırsak çökme riski olur.
    @MainActor
    func processImage(_ image: UIImage) async {
        // Yeni bir fotoğraf geldiğinde önceki sonuçları temizliyoruz ve
        // "işleniyor" durumuna geçiyoruz, ekran bunu görüp yükleniyor animasyonu gösterecek.
        selectedImage = image
        draftItems = []
        state = .processing

        do {
            // 1. Adım: fotoğraftaki tüm yazıları satır satır oku
            let lines = try await ocrService.recognizeTextLines(from: image)

            // 2. Adım: bu satırları ürün adı + fiyat olarak ayrıştır
            let parsedLines = ocrService.parseLines(lines)

            // Eğer hiçbir satırdan anlamlı bir ürün+fiyat çıkaramadıysak,
            // kullanıcıya durumu açıklayan bir hata gösteriyoruz. Fotoğraf
            // bulanık olabilir ya da fiş formatı beklediğimizden farklı olabilir.
            guard !parsedLines.isEmpty else {
                state = .error(
                    "Fişten ürün ve fiyat bilgisi ayrıştırılamadı. Lütfen fişi daha net çekip tekrar deneyin ya da kalemleri elle ekleyin."
                )
                return
            }

            // 3. Adım: her ayrıştırılmış satırı, düzenlenebilir bir DraftReceiptItem'a
            // çeviriyoruz ve bu sırada kategorizasyon servisini çağırıp otomatik
            // kategori ataması yapıyoruz.
            draftItems = parsedLines.map { parsed in
                DraftReceiptItem(
                    id: UUID(),
                    name: parsed.productName,
                    priceText: String(format: "%.2f", parsed.price),
                    category: categorizationService.categorize(productName: parsed.productName),
                    rawOCRText: parsed.rawText
                )
            }

            // Artık ekran "sonuçları gözden geçir" moduna geçebilir
            state = .reviewing
        } catch let ocrError as OCRError {
            // OCRService'in fırlattığı kendi hata tiplerimizi yakalayıp
            // kullanıcı dostu mesajı ekrana taşıyoruz.
            state = .error(ocrError.errorDescription ?? "Bilinmeyen bir OCR hatası oluştu.")
        } catch {
            // Beklemediğimiz herhangi bir hata olursa da kullanıcıyı bilgilendiriyoruz,
            // uygulama sessizce çökmesin ya da takılıp kalmasın diye.
            state = .error("Beklenmeyen bir hata oluştu: \(error.localizedDescription)")
        }
    }

    // MARK: - Elle Düzenleme

    // Kullanıcı OCR'ın kaçırdığı bir ürünü elle eklemek isterse bu fonksiyon
    // boş bir satır oluşturuyor, kullanıcı da ismini/fiyatını kendi giriyor.
    func addEmptyItem() {
        draftItems.append(
            DraftReceiptItem(id: UUID(), name: "", priceText: "0.00", category: .diger, rawOCRText: "")
        )
        // Eğer henüz hiç fotoğraf işlenmediyse (state hala idle ise) ama kullanıcı
        // direkt elle kalem eklemek istiyorsa, ekranı "reviewing" moduna alıyoruz
        // ki kalem listesi ve kaydet butonu görünsün.
        if case .idle = state { state = .reviewing }
    }

    // Kullanıcı bir kalemi silmek isterse (yanlış okunmuş ya da gereksiz bir satırsa)
    // bu fonksiyon o kalemi listeden çıkarıyor.
    func deleteItem(_ item: DraftReceiptItem) {
        draftItems.removeAll { $0.id == item.id }
    }

    // MARK: - Kaydetme

    // Kullanıcı "Fişi Kaydet" butonuna bastığında çalışan fonksiyon.
    // Geçici (draft) kalemleri gerçek SwiftData nesnelerine (Receipt + ReceiptItem)
    // dönüştürüp veritabanına yazıyoruz.
    @discardableResult
    func saveReceipt(modelContext: ModelContext) -> Receipt? {
        // Kaydedilecek hiç kalem yoksa boşuna işlem yapmıyoruz
        guard !draftItems.isEmpty else { return nil }

        // Yeni bir Receipt (fiş) nesnesi oluşturuyoruz, market adı boşsa
        // varsayılan bir isim veriyoruz.
        let receipt = Receipt(storeName: storeName.isEmpty ? "Bilinmeyen Market" : storeName)

        // Çekilen fotoğrafı da sıkıştırıp (jpegData ile) fişle birlikte saklıyoruz,
        // böylece detay ekranında kullanıcı orijinal fişi tekrar görebiliyor.
        receipt.imageData = selectedImage?.jpegData(compressionQuality: 0.6)

        // Adı boş olan (kullanıcının silmeyi unuttuğu ya da hiç doldurmadığı)
        // taslak satırları atlıyoruz, sadece gerçek isimli ürünleri kaydediyoruz.
        for draft in draftItems where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let item = ReceiptItem(
                name: draft.name,
                price: draft.price,
                category: draft.category,
                rawOCRText: draft.rawOCRText
            )
            item.receipt = receipt
            receipt.items.append(item)
        }

        // Yeni fişi veritabanı bağlamına (context) ekliyoruz
        modelContext.insert(receipt)

        do {
            // Değişiklikleri diske gerçekten yazıyoruz
            try modelContext.save()
        } catch {
            state = .error("Fiş kaydedilirken bir hata oluştu: \(error.localizedDescription)")
            return nil
        }

        // Kayıt başarılıysa ekranı sıfırlıyoruz ki kullanıcı yeni bir fiş
        // taramaya hazır, temiz bir ekranla başlasın.
        reset()
        return receipt
    }

    // Ekranı en baştaki haline döndürüyoruz: fotoğraf yok, kalem yok,
    // market adı varsayılan, durum "idle".
    func reset() {
        selectedImage = nil
        draftItems = []
        storeName = "Bilinmeyen Market"
        state = .idle
    }
}
