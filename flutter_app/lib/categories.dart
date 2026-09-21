import 'l10n.dart';

/// Mahsulot kategoriyalari. Rasm kartochkalari `assets/img/cat/<slug>-<uz|ru|en>.webp`
/// (kartochkadagi yozuv tanlangan tilga mos rasm orqali chiqadi).
class Category {
  final String slug;
  final String uz;
  final String ru;
  final String en;
  const Category(this.slug, this.uz, this.ru, this.en);

  String get name => switch (L10n.lang) { AppLang.ru => ru, AppLang.en => en, _ => uz };
  String get asset => 'assets/img/cat/$slug-${L10n.lang.name}.webp';
}

const categories = [
  Category('school', 'Maktab', 'Школа', 'School'),
  Category('women', 'Ayollar', 'Женщинам', 'Women'),
  Category('shoes', 'Poyabzal', 'Обувь', 'Shoes'),
  Category('kids', 'Bolalar', 'Детям', 'Kids'),
  Category('men', 'Erkaklar', 'Мужчинам', 'Men'),
  Category('home', "Uy-ro'zg'or", 'Дом', 'Home'),
  Category('beauty', "Go'zallik", 'Красота', 'Beauty'),
  Category('accessories', 'Aksessuarlar', 'Аксессуары', 'Accessories'),
  Category('electronics', 'Elektronika', 'Электроника', 'Electronics'),
  Category('toys', "O'yinchoqlar", 'Игрушки', 'Toys'),
  Category('furniture', 'Mebel', 'Мебель', 'Furniture'),
  Category('adult-products', 'Kattalar uchun', 'Для взрослых', 'Adult products'),
  Category('groceries', 'Oziq-ovqat', 'Продукты', 'Groceries'),
  Category('flowers', 'Gullar', 'Цветы', 'Flowers'),
  Category('appliances', 'Maishiy texnika', 'Бытовая техника', 'Appliances'),
  Category('pet-supplies', 'Uy hayvonlari', 'Зоотовары', 'Pet supplies'),
  Category('sports', 'Sport', 'Спорт', 'Sports'),
  Category('car-accessories', 'Avto aksessuarlar', 'Автотовары', 'Car accessories'),
  Category('books', 'Kitoblar', 'Книги', 'Books'),
  Category('jewelry', 'Zargarlik', 'Украшения', 'Jewelry'),
  Category('tools', 'Asboblar', 'Инструменты', 'Tools'),
  Category('garden', "Bog'", 'Сад', 'Garden'),
  Category('health', 'Salomatlik', 'Здоровье', 'Health'),
  Category('adaptive-products', 'Adaptiv mahsulotlar', 'Адаптивные товары', 'Adaptive products'),
  Category('stationery', 'Kanselyariya', 'Канцтовары', 'Stationery'),
];

Category? categoryOf(String? slug) => slug == null ? null : categories.where((c) => c.slug == slug).firstOrNull;
