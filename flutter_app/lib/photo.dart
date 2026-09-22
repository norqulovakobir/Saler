import 'package:image_picker/image_picker.dart';

/// Rasm tanlash sozlamalari — bitta joyda.
///
/// Rasmlar hozir Cloudflare D1 bazasida saqlanadi (R2 obyekt ombori yoqilmagan).
/// D1 ning bepul chegarasi 500 MB, shuning uchun har bir rasmning hajmi
/// muhim: 1280px/85 sifatida bitta rasm ~300 KB, 1080px/72 da esa ~120 KB
/// bo'ladi — ya'ni o'sha bepul joyga taxminan uch baravar ko'p rasm sig'adi.
/// Ko'z bilan farq deyarli sezilmaydi, chunki telefonda rasm baribir
/// ekran kengligida ko'rsatiladi.
///
/// R2 yoqilganda bu qiymatlarni oshirish mumkin (`/api/health` da
/// `"media":"r2"` bo'ladi).
class PhotoPick {
  /// Mahsulot rasmlari: katalogda va mahsulot sahifasida to'liq ko'rinadi
  static const productWidth = 1080.0;
  static const productQuality = 72;

  /// Logo va avatar: doim kichik doirada ko'rsatiladi
  static const logoWidth = 400.0;
  static const logoQuality = 78;

  /// Mahsulot uchun bitta rasm
  static Future<XFile?> product(ImageSource source) =>
      ImagePicker().pickImage(source: source, maxWidth: productWidth, imageQuality: productQuality);

  /// Mahsulot uchun bir nechta rasm
  static Future<List<XFile>> products() =>
      ImagePicker().pickMultiImage(maxWidth: productWidth, imageQuality: productQuality);

  /// Logo, avatar yoki hujjat rasmi
  static Future<XFile?> logo(ImageSource source) =>
      ImagePicker().pickImage(source: source, maxWidth: logoWidth, imageQuality: logoQuality);
}
