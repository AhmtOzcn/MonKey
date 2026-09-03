import SwiftUI
import SwiftData

// Uygulamanın başlangıç noktası. Telefon "MonKey" uygulamasını açtığında
// ilk çalışan yer burası. @main işareti Swift'e "programı buradan başlat" diyor.
@main
struct MonKeyApp: App {

    // SwiftData'nın veritabanı kutusunu (ModelContainer) burada bir kere kuruyoruz.
    // Bu kutu, uygulama boyunca Receipt ve ReceiptItem nesnelerinin nerede ve
    // nasıl saklanacağını yönetiyor. "lazy" gibi çalışan bir yapı olduğu için
    // sadece bir kere, uygulama açılırken oluşturuluyor.
    var sharedModelContainer: ModelContainer = {
        // Hangi modelleri (tabloları) saklayacağımızı burada listeliyoruz
        let schema = Schema([
            Receipt.self,
            ReceiptItem.self
        ])

        // isStoredInMemoryOnly: false demek "verileri telefonun diskine kalıcı olarak yaz,
        // uygulama kapanınca silinmesin" demek. true yaparsan sadece test amaçlı,
        // uygulama kapanınca her şey uçar.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Veritabanı kutusu hiç kurulamazsa uygulamanın zaten çalışması mümkün değil,
            // bu yüzden burada programı durduruyoruz (fatalError). Normal şartlarda
            // bu satıra hiç düşülmemesi gerekir.
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        // Oluşturduğumuz veritabanı kutusunu tüm uygulamaya (her ekrana) tanıtıyoruz.
        // Bu sayede herhangi bir View içinde @Environment(\.modelContext) ya da
        // @Query yazarak doğrudan veritabanına erişebiliyoruz.
        .modelContainer(sharedModelContainer)
    }
}

// Uygulamanın en alt kısmındaki sekme çubuğunu (tab bar) oluşturuyoruz.
// Kullanıcı "Tara" ve "Özet" sekmeleri arasında gezinebiliyor.
struct RootTabView: View {
    var body: some View {
        TabView {
            ScannerView()
                .tabItem {
                    Label("Tara", systemImage: "camera.viewfinder")
                }

            DashboardView()
                .tabItem {
                    Label("Özet", systemImage: "chart.pie.fill")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Receipt.self, ReceiptItem.self], inMemory: true)
}
