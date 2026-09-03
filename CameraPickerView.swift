import SwiftUI
import UIKit

// SwiftUI'da henüz kamerayı doğrudan açan hazır bir bileşen yok (PhotosPicker
// sadece galeriyi açar). Bu yüzden Apple'ın eski ama hala çalışan
// UIImagePickerController'ını SwiftUI'nin anlayacağı bir "köprü" ile sarmalıyoruz.
// Bu köprüye UIViewControllerRepresentable deniyor.
struct CameraPickerView: UIViewControllerRepresentable {

    // Kamera ekranı kapandığında (fotoğraf çekilince ya da iptal edilince)
    // bu view'ı ekrandan kaldırmak için kullanıyoruz.
    @Environment(\.dismiss) private var dismiss

    // Fotoğraf çekildiğinde dışarıya (ScannerView'a) haber vermek için
    // kullandığımız basit bir "callback" (geri çağrı) fonksiyonu.
    var onImagePicked: (UIImage) -> Void

    // SwiftUI bu view'ı ilk gösterdiğinde çağrılır, gerçek UIKit ekranını burada kuruyoruz.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator   // Olayları kim dinleyecek (aşağıdaki Coordinator)
        picker.sourceType = .camera              // Galeri değil, doğrudan kamerayı aç
        picker.cameraCaptureMode = .photo         // Video değil, fotoğraf modu
        picker.allowsEditing = false              // Kullanıcı fotoğrafı kırpmasın, ham haliyle alalım
        return picker
    }

    // SwiftUI, view'ın "state"i değiştiğinde bu fonksiyonu çağırır ama bizim
    // burada güncellenecek bir şeyimiz yok, bu yüzden boş bırakıyoruz.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // Güncelleme gerekmiyor
    }

    // SwiftUI ile UIKit arasındaki olayları (fotoğraf çekildi, iptal edildi vb.)
    // dinleyecek olan "Coordinator" nesnesini oluşturuyoruz.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // Simülatörde fiziksel kamera olmadığı için kamera butonunu güvenle
    // devre dışı bırakabilmek adına bu kontrolü dışarıya (ScannerView'a) açıyoruz.
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    // UIImagePickerController'ın olaylarını (delegate) dinleyen yardımcı sınıf.
    // SwiftUI'de doğrudan delegate kullanamadığımız için bu köprüye ihtiyacımız var.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        // Kullanıcı fotoğrafı çekip onayladığında burası çalışır.
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Çekilen orijinal fotoğrafı alıp dışarıdaki callback'e (onImagePicked)
            // gönderiyoruz, ScannerView bunu yakalayıp OCR sürecini başlatacak.
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        // Kullanıcı "İptal" derse sadece ekranı kapatıyoruz, başka bir şey yapmıyoruz.
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
