import Foundation

// Bu servisin işi basit: elimize bir ürün adı geliyor (örn. "Tam Yağlı Süt"),
// biz de bunun hangi kategoriye ait olduğuna karar veriyoruz.
// Yapay zeka falan kullanmıyoruz, düz mantıkla çalışıyor: bir kelime listesi
// tutuyoruz ve ürün adında bu kelimelerden biri geçiyorsa o kategoriyi seçiyoruz.
// Basit ama gayet işe yarar bir yöntem, istersen ileride kelime listesini
// genişleterek daha akıllı hale getirebilirsin.
struct CategorizationService {

    // Her kategori için "bu kelimelerden biri geçerse bu kategoridir" dediğimiz liste.
    // Örneğin ürün adında "süt" veya "ekmek" geçiyorsa bunu Gıda sayıyoruz.
    // Liste büyüdükçe kategorizasyon daha isabetli olur, yeni ürün gördükçe
    // buraya ekleme yapman yeterli.
    private let keywordMap: [ReceiptCategory: [String]] = [
        .gida: [
            "süt", "ekmek", "peynir", "yumurta", "yoğurt", "tereyağ", "zeytin",
            "domates", "salatalık", "biber", "patates", "soğan", "elma", "muz",
            "portakal", "un", "şeker", "tuz", "makarna", "pirinç", "bulgur",
            "yağ", "çay", "kahve", "bal", "reçel", "kraker", "bisküvi", "çikolata",
            "meyve suyu", "kola", "gazoz", "et", "tavuk", "balık", "sucuk",
            "salam", "sosis", "kek", "pasta", "dondurma", "kuruyemiş", "fındık",
            "ceviz", "fıstık", "mercimek", "nohut", "fasulye", "sebze", "meyve",
            "ayran", "kaymak", "margarin", "yulaf", "gofret", "cips", "su",
            "limonata", "baharat", "sos", "ketçap", "mayonez", "hardal"
        ],
        .hijyenTemizlik: [
            "şampuan", "sabun", "deterjan", "yumuşatıcı", "bulaşık", "çamaşır",
            "diş macunu", "diş fırçası", "peçete", "tuvalet kağıdı", "kağıt havlu",
            "temizlik", "çöp poşeti", "bez", "sünger", "cif", "domestos", "vim",
            "finish", "ariel", "omo", "persil", "bingo", "fairy", "colgate",
            "signal", "pril", "duş jeli", "vücut losyonu", "krem", "parfüm",
            "deodorant", "pamuk", "islak mendil", "kolonya", "jilet", "tıraş"
        ],
        .saglikMedikal: [
            "parol", "aspirin", "vitamin", "ilaç", "ağrı kesici", "öksürük",
            "şurup", "gargara", "maske", "dezenfektan", "bandaj", "yara bandı",
            "termometre", "gripin", "majezik", "apranax", "vermidon", "dolorex",
            "supradyn", "cinkaramin", "medikal", "eczane", "reçete", "pastil",
            "antibiyotik", "damla", "merhem"
        ],
        .tutunAlkol: [
            "sigara", "tütün", "bira", "rakı", "şarap", "votka", "viski", "cin",
            "kokteyl", "puro", "nargile", "marlboro", "parliament", "camel",
            "winston", "kent", "tekel", "efes", "bomonti", "yeni rakı", "tuborg",
            "corona", "heineken", "malt"
        ]
    ]

    // Bir ürün adı verildiğinde, kelime listelerinde tarama yapıp uygun kategoriyi
    // döndüren fonksiyon. Hiçbir kelimeyle eşleşmezse "Diğer" kategorisine düşer,
    // yani hiçbir ürün kategorisiz kalmaz.
    func categorize(productName: String) -> ReceiptCategory {
        // Önce ürün adını küçük harfe çeviriyoruz, çünkü fişte "SÜT" büyük harf
        // yazılmış olabilir ama bizim listemizde küçük harfle "süt" var.
        // tr_TR locale'i kullanıyoruz ki Türkçe'ye özgü "İ/i" gibi harf
        // farklılıkları doğru işlensin.
        let normalized = productName.lowercased(with: Locale(identifier: "tr_TR"))

        // "Diğer" hariç tüm kategorileri sırayla deniyoruz. İlk eşleşen
        // kategoriyi direkt döndürüyoruz (yani en üstteki eşleşme kazanır).
        for category in ReceiptCategory.allCases where category != .diger {
            guard let keywords = keywordMap[category] else { continue }
            for keyword in keywords {
                // "contains" ile ürün adının içinde bu kelime geçiyor mu diye bakıyoruz.
                // Yani "süt" kelimesi hem "süt" hem "yayık sütü" gibi ürünlerde de yakalanır.
                if normalized.contains(keyword) {
                    return category
                }
            }
        }

        // Hiçbir eşleşme bulunamadıysa bu ürünü "Diğer" olarak işaretliyoruz.
        // Kullanıcı isterse ScannerView veya ReceiptDetailView üzerinden bunu
        // elle doğru kategoriye taşıyabilir.
        return .diger
    }
}
