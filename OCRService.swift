import Foundation
import Vision
import UIKit

// Bu dosyanın işi tek: elimizdeki fiş fotoğrafını "okumak".
// Apple'ın kendi görüntü işleme kütüphanesi olan Vision'ı kullanıyoruz,
// yani hiçbir dış kütüphane indirmemize gerek yok. Vision fotoğraftaki
// yazıları satır satır bulup bize düz metin olarak veriyor, biz de
// o metnin içinden ürün adını ve fiyatı ayıklıyoruz.

// MARK: - Hata Tipleri

// OCR işlemi sırasında ters gidebilecek durumları burada topluyoruz.
// Her birinin kullanıcıya gösterilecek anlaşılır bir Türkçe açıklaması var,
// yani hata olduğunda ekrana "Error: nil" gibi bir şey değil, gerçek bir
// yönlendirme mesajı çıkacak.
enum OCRError: LocalizedError {
    case invalidImage       // Fotoğraf bozuk ya da işlenemez formatta
    case noTextFound        // Vision fotoğrafta hiç yazı bulamadı
    case recognitionFailed(String)  // Vision'ın kendi içinden bir hata geldi

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Fotoğraf okunamadı. Lütfen daha net bir fiş fotoğrafı çekin veya seçin."
        case .noTextFound:
            return "Fişte okunabilir bir metin bulunamadı. Lütfen fişi daha iyi ışık altında ve düz bir şekilde tekrar çekin."
        case .recognitionFailed(let reason):
            return "Metin tanıma başarısız oldu: \(reason)"
        }
    }
}

// Fişten ayrıştırdığımız TEK BİR SATIRIN sonucu. Yani "Süt ... 24,90" gibi
// bir satırı işleyip buradan "Süt" ve 24.90 çıkarıyoruz.
struct ParsedReceiptLine {
    let rawText: String       // Vision'ın okuduğu orijinal, ham satır
    let productName: String   // Fiyatı çıkarınca geriye kalan ürün ismi
    let price: Double         // Satırdan çözdüğümüz sayısal fiyat
}

// Asıl OCR işini yapan servis. İki ana görevi var:
// 1) recognizeTextLines: fotoğraftaki tüm yazıları satır satır okumak
// 2) parseLines: o satırları ürün adı + fiyat şeklinde anlamlandırmak
struct OCRService {

    // Verilen fotoğrafı Vision'a gönderip içindeki yazıları satır satır alıyoruz.
    // Bu işlem "async" çünkü Vision biraz zaman alabiliyor (özellikle büyük
    // fotoğraflarda), bu yüzden arka planda çalışıp sonucu bekliyoruz.
    func recognizeTextLines(from image: UIImage) async throws -> [String] {
        // UIImage'ı Vision'ın anlayacağı CGImage formatına çeviriyoruz.
        // Bu dönüşüm bazen başarısız olabilir (örn. bozuk dosya), o yüzden
        // önce kontrol ediyoruz.
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // Vision'ın kendi API'si "completion handler" (kapanış fonksiyonu) ile
        // çalışıyor, yani sonucu direkt döndürmüyor, bittiğinde bir fonksiyonu
        // çağırıyor. Biz burada bunu modern async/await yapısına çeviriyoruz ki
        // ViewModel tarafında "await ocrService.recognizeTextLines(...)" diye
        // sade bir şekilde çağırabilelim.
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                // Vision bir hata bildirdiyse, bunu kendi hata tipimize çevirip fırlatıyoruz
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                // Vision'ın bulduğu her "metin bloğu" bir VNRecognizedTextObservation.
                // Hiçbiri yoksa demek ki fotoğrafta okunacak yazı bulunamadı.
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                // Her bloğun Vision'ın en emin olduğu okuma tahminini (topCandidates(1))
                // alıyoruz. Yani "bu yazı %90 ihtimalle böyle" dediği ilk seçeneği kullanıyoruz.
                let lines = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                if lines.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: lines)
                }
            }

            // .accurate demek: Vision biraz daha yavaş ama daha isabetli okusun.
            // Fiş gibi küçük ve yoğun yazılarda hız yerine doğruluğu tercih ediyoruz.
            request.recognitionLevel = .accurate

            // Vision'ın kendi dil bilgisiyle "muhtemelen bu kelime bu olmalı" diye
            // düzeltme yapmasını istiyoruz, bu da doğruluğu artırıyor.
            request.usesLanguageCorrection = true

            // Fişlerde hem Türkçe ürün adları hem bazen İngilizce marka isimleri
            // olabiliyor, ikisini de tanımasını istiyoruz.
            request.recognitionLanguages = ["tr-TR", "en-US"]

            // Fiş yazıları genelde çok küçük punto oluyor, bu değeri düşük tutarak
            // Vision'a "küçük yazıları da gözden kaçırma" diyoruz.
            request.minimumTextHeight = 0.015

            // Fotoğrafın döndürülmüş halini (kameradan gelen fotoğraflar bazen yan
            // yatık olabiliyor) doğru yönde işlemesi için orientation bilgisini veriyoruz.
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: image.cgImagePropertyOrientation,
                options: [:]
            )

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // Vision'dan gelen ham satırları alıp gerçek ürün + fiyat listesine çeviriyoruz.
    // Türkiye'deki market fişlerinde genelde format şöyledir:
    //   "SÜT TAM YAĞLI 1L        24,90"
    // yani ürün adı solda, fiyat sağda. Biz de bu mantıkla çalışıyoruz.
    func parseLines(_ lines: [String]) -> [ParsedReceiptLine] {
        // Fişlerde "TOPLAM", "KDV", "NAKİT" gibi satırlar da oluyor ama bunlar
        // birer ürün değil, fişin özet bilgileri. Bu kelimeleri gördüğümüzde
        // o satırı tamamen atlıyoruz ki yanlışlıkla "ürün" gibi eklenmesin.
        let ignoredKeywords = [
            "toplam", "ara toplam", "kdv", "nakit", "kredi", "para üstü",
            "fiş no", "fatura", "kasiyer", "tarih", "saat", "vergi", "no:",
            "müşteri", "iade", "değişim", "teşekkür", "tel:", "adres",
            "www.", "iyi günler", "hoşgeldiniz", "vergi no", "mersis", "z raporu"
        ]

        // Bu regex (düzenli ifade), bir satırın SONUNDA duran bir fiyatı yakalamak
        // için yazıldı. Örnek eşleşmeler: "24,90", "1.234,50", "24,90 TL".
        // Kısaca: "satırın en sonunda virgüllü/noktalı iki haneli bir sayı var mı?"
        // diye soruyoruz.
        let pricePattern = #"(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})\s*(?:TL|₺)?\s*$"#
        guard let priceRegex = try? NSRegularExpression(pattern: pricePattern, options: []) else {
            return []
        }

        var results: [ParsedReceiptLine] = []

        for rawLine in lines {
            // Satırın başındaki/sonundaki boşlukları temizliyoruz
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Küçük harfe çeviriyoruz ki "TOPLAM" da "toplam" da "Toplam" da yakalansın
            let lowercased = line.lowercased(with: Locale(identifier: "tr_TR"))

            // Eğer bu satır özet/başlık bilgisi içeriyorsa (yukarıdaki listeden biri
            // geçiyorsa), bunu bir ürün olarak değerlendirmiyoruz, direkt atlıyoruz.
            if ignoredKeywords.contains(where: { lowercased.contains($0) }) {
                continue
            }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            // Satırda regex'imize uyan bir fiyat var mı diye bakıyoruz.
            // Yoksa bu satırda muhtemelen ürün+fiyat bilgisi yok, atlıyoruz.
            guard let match = priceRegex.firstMatch(in: line, options: [], range: fullRange),
                  match.range(at: 1).location != NSNotFound else {
                continue
            }

            // Bulduğumuz fiyat metnini ("1.234,50" gibi) gerçek bir Double'a çeviriyoruz.
            // Türkçe'de nokta binlik ayracı, virgül ondalık ayracı olduğu için
            // önce noktaları siliyoruz, sonra virgülü noktaya çeviriyoruz
            // (İngilizce/bilgisayar formatına dönüştürmüş oluyoruz).
            let priceString = nsLine.substring(with: match.range(at: 1))
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")

            // Sayıya çevrilemiyorsa ya da mantıksız bir değerse (0 veya çok büyük)
            // bu satırı güvenilir bulmuyoruz ve atlıyoruz.
            guard let price = Double(priceString), price > 0, price < 100_000 else {
                continue
            }

            // Satırdan fiyat kısmını çıkarınca geriye kalan kısım ürün adı oluyor.
            var productName = nsLine.replacingCharacters(in: match.range, with: "")
            productName = productName.trimmingCharacters(in: .whitespacesAndNewlines)

            // Ürün adı 1-2 karakterden kısaysa muhtemelen gerçek bir ürün adı değil,
            // Vision'ın yanlış okuduğu bir kırıntıdır, bu yüzden onu da eliyoruz.
            guard productName.count >= 2 else { continue }

            results.append(
                ParsedReceiptLine(rawText: line, productName: productName, price: price)
            )
        }

        return results
    }
}

// UIImage'ın döndürülme bilgisini Vision'ın anlayacağı formata çeviren
// küçük bir yardımcı. Kameradan gelen fotoğraflar bazen "yatık" kaydediliyor,
// bu bilgi olmadan Vision yazıları ters okuyabilir.
private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
