import 'package:image_picker/image_picker.dart';

/// Rasm tanlash sozlamalari — bitta joyda.
///
/// Rasmlar R2 obyekt omborida saqlanadi (`/api/health` da
/// `"media":{"store":"r2"}`), ya'ni D1 ning 500 MB chegarasi endi to'siq
/// emas. Shuning uchun sifat oshirildi: 1080px/72 da rasm Reels'da va
/// do'kon kartochkasida hira ko'rinardi — ekran kengligiga cho'zilganda
/// siqilish izlari sezilib qolardi.
class PhotoPick {
  /// Mahsulot rasmlari: Reels'da butun ekranni egallaydi, shuning uchun
  /// telefon ekrani kengligidan kattaroq olinadi
  static const productWidth = 1600.0;
  static const productQuality = 90;

  /// Logo va avatar: doim kichik doirada ko'rsatiladi
  static const logoWidth = 512.0;
  static const logoQuality = 88;

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
