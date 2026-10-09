# SafeChat - Görüntülü, Sesli ve Mesajlaşma Mobil Uygulaması (Flutter & MariaDB/Python)

Bu proje, Flutter (Dart) ve özel Python/MariaDB altyapısı üzerine inşa edilmiş, kullanıcı adı & şifre ile kayıt/giriş yapılan, birebir anlık mesajlaşma ile WebRTC destekli sesli ve görüntülü arama özelliklerine sahip tam teşekküllü ve güvenli bir mobil uygulamadır.

---

## 🚀 Özellikler

1. **Kullanıcı Adı & Şifre ile Kimlik Doğrulama:**
   - Benzersiz kullanıcı adı (`@kullaniciadi`) kontrolü.
   - Güvenli şifreli kayıt ve giriş yapma ([`auth_service.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/services/auth_service.dart)).
   - Çevrimiçi / Çevrimdışı ve Son Görülme durum takibi.

2. **Gerçek Zamanlı Birebir Mesajlaşma:**
   - Anlık mesaj iletimi ([`chat_service.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/services/chat_service.dart)).
   - Okundu bilgisi (Tek tık / Çift tık `done_all`).
   - SafeChat neo-dark degradeli sohbet balonları ve tasarımı ([`chat_screen.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/screens/chat/chat_screen.dart)).

3. **HD Görüntülü ve Sesli Konuşma (WebRTC):**
   - WebRTC sinyalleşmesi (SDP Offer / Answer ve ICE Candidates) ([`signaling_service.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/services/signaling_service.dart)).
   - Tam ekran uzak video + PIP (Küçük pencere) yerel video görüntüsü ([`call_screen.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/screens/call/call_screen.dart)).
   - Ön / arka kamera değiştirme, mikrofon susturma (Mute) ve video kapatma.
   - Gelen arama ekranı ve Kabul / Reddet desteği ([`incoming_call_dialog.dart`](file:///c:/Users/BGame/Desktop/Konuşma%20Ve%20mesajlaşma%20Uygulaması/lib/screens/call/incoming_call_dialog.dart)).

---

## 📁 Proje Yapısı

```
lib/
├── constants/
│   └── app_colors.dart         # SafeChat renk paleti ve tema sabitleri
├── models/
│   ├── user_model.dart         # Kullanıcı veri modeli
│   ├── message_model.dart      # Mesaj veri modeli
│   └── call_model.dart         # Arama (Call) sinyal modeli
├── services/
│   ├── auth_service.dart       # Giriş / Kayıt / Oturum yönetimi
│   ├── chat_service.dart       # Mesajlaşma & Kullanıcı akışı
│   └── signaling_service.dart  # WebRTC Ses/Video arama motoru
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart   # Giriş Ekranı
│   │   └── register_screen.dart# Kayıt Olma Ekranı
│   ├── home/
│   │   └── home_screen.dart    # Sohbetler, Kişiler ve Aramalar Sekmeleri
│   ├── chat/
│   │   └── chat_screen.dart    # Mesajlaşma Odası
│   └── call/
│       ├── call_screen.dart    # Sesli/Görüntülü Görüşme Ekranı
│       └── incoming_call_dialog.dart # Gelen Arama Bildirim Ekranı
└── main.dart                   # Uygulama Başlangıç Noktası
```

---

## 🛠️ Nasıl Çalıştırılır?

1. **Flutter Ortamı:**
   - Flutter SDK `C:\src\flutter\bin` konumuna otomatik olarak klonlanmıştır.
   - Terminalde `C:\src\flutter\bin\flutter doctor` çalıştırabilirsiniz veya sistem PATH'inize `C:\src\flutter\bin` ekleyebilirsiniz.

2. **Paketleri Yükleme:**
   ```bash
   C:\src\flutter\bin\flutter pub get
   ```

3. **Firebase Bağlantısı:**
   - [Firebase Console](https://console.firebase.google.com/) üzerinden bir proje oluşturun.
   - **Authentication** (Email/Password) ve **Cloud Firestore** hizmetlerini aktif edin.
   - Android için `google-services.json` dosyasını `android/app/` içerisine koyun veya `flutterfire configure` çalıştırın.

4. **Uygulamayı Başlatma:**
   ```bash
   C:\src\flutter\bin\flutter run
   ```
