/// Do'kon kartochkasi karuselidagi bitta mahsulot: rasm, nom va narx.
///
/// Server `previewItems` bermasa (eski versiya), faqat rasm qoladi —
/// [name] bo'sh, [price] esa null bo'ladi va kartochka narx qatorini
/// umuman ko'rsatmaydi. Narx 0 bo'lsa "Narx kelishiladi" chiqadi.
class ShopPreviewItem {
  final String id;
  final String name;
  final int? price;
  final int? oldPrice; // chegirma bo'lsa: ustidan chizilgan eski narx
  final String photo;

  const ShopPreviewItem({
    this.id = '',
    this.name = '',
    this.price,
    this.oldPrice,
    required this.photo,
  });

  factory ShopPreviewItem.fromJson(Map<String, dynamic> j) => ShopPreviewItem(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        price: (j['price'] as num?)?.round(),
        oldPrice: (j['oldPrice'] as num?)?.round(),
        photo: j['photo'] ?? '',
      );
}

class Shop {
  final String id;
  final String name;
  final String sellerName;
  final String phone;
  final String? logo;
  final String description;
  final double? lat;
  final double? lon;
  final String? address;
  final int productCount;
  final String? login;
  final String? ownerName;

  /// AI yordamchi tavsiyasida: foydalanuvchidan masofa (km), bo'lmasa null
  final double? distanceKm;

  /// Reyting: bajarilgan sotuvlar soni, 1.0–5.0 baho, daraja (Yangi/Bronza/Kumush/Oltin/Platina), o'rin
  final int sales;
  final double rating;
  final String level;
  final int? rank;
  final int followers; // obunachilar soni
  final bool following; // joriy foydalanuvchi obuna bo'lganmi

  /// Kartochka fonida aylanadigan mahsulot rasmlari (har mahsulotdan bittadan)
  final List<String> preview;

  /// Shu rasmlarning mahsulot ma'lumoti: nom va narx ham kartochkada chiqadi
  final List<ShopPreviewItem> previewItems;

  Shop({
    required this.id,
    required this.name,
    required this.sellerName,
    required this.phone,
    this.logo,
    this.description = '',
    this.lat,
    this.lon,
    this.address,
    this.productCount = 0,
    this.login,
    this.ownerName,
    this.distanceKm,
    this.sales = 0,
    this.rating = 1,
    this.level = 'Yangi',
    this.rank,
    this.followers = 0,
    this.following = false,
    this.preview = const [],
    this.previewItems = const [],
  });

  /// Eski server faqat `preview` (rasm ro'yxati) qaytaradi — o'shanda ham
  /// karusel ishlashi uchun rasmlar mahsulotsiz elementga o'raladi.
  static List<ShopPreviewItem> _previewItems(Map<String, dynamic> j) {
    final items = j['previewItems'];
    if (items is List && items.isNotEmpty) {
      return items
          .whereType<Map>()
          .map((e) => ShopPreviewItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.photo.isNotEmpty)
          .toList();
    }
    return (j['preview'] as List?)
            ?.whereType<String>()
            .map((p) => ShopPreviewItem(photo: p))
            .toList() ??
        const [];
  }

  factory Shop.fromJson(Map<String, dynamic> j) {
    final loc = j['location'];
    return Shop(
      id: j['id'] ?? '',
      name: j['name'] ?? '',
      sellerName: j['sellerName'] ?? '',
      phone: j['phone'] ?? '',
      logo: j['logo'],
      description: j['description'] ?? '',
      lat: loc is Map ? (loc['lat'] as num?)?.toDouble() : null,
      lon: loc is Map ? (loc['lon'] as num?)?.toDouble() : null,
      address: loc is Map ? loc['address'] : null,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      sales: (j['sales'] as num?)?.toInt() ?? 0,
      rating: (j['rating'] as num?)?.toDouble() ?? 1,
      level: j['level'] ?? 'Yangi',
      rank: (j['rank'] as num?)?.toInt(),
      productCount: (j['productCount'] ?? 0) as int,
      login: j['login'],
      ownerName: j['ownerName'],
      followers: (j['followers'] as num?)?.toInt() ?? 0,
      following: j['following'] == true,
      preview: (j['preview'] as List?)?.whereType<String>().toList() ?? const [],
      previewItems: _previewItems(j),
    );
  }
}

class Product {
  final String id;
  final String shopId;
  final String name;
  final String? category; // kategoriya slug
  final int price;
  final String description;
  final List<String> photos;
  final bool active;
  final int views;

  Product({
    required this.id,
    required this.shopId,
    required this.name,
    this.category,
    required this.price,
    this.description = '',
    this.photos = const [],
    this.active = true,
    this.views = 0,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] ?? '',
        shopId: j['shopId'] ?? '',
        name: j['name'] ?? '',
        category: j['category'],
        price: ((j['price'] ?? 0) as num).round(),
        description: j['description'] ?? '',
        photos: List<String>.from(j['photos'] ?? const []),
        active: j['active'] != false,
        views: (j['views'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'shopId': shopId,
        'name': name,
        'category': category,
        'price': price,
        'description': description,
        'photos': photos,
      };
}

class OrderItem {
  final String name;
  final int price;
  final int qty;
  OrderItem({required this.name, required this.price, required this.qty});
  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        name: j['name'] ?? '',
        price: ((j['price'] ?? 0) as num).round(),
        qty: (j['qty'] ?? 1) as int,
      );
}

class Order {
  final String id;
  final String status;
  final DateTime createdAt;
  final String productName;
  final int price;
  final String customerName;
  final String phone;
  final String buyerLink;
  final List<OrderItem> items;
  final String shopName;
  final String shopPhone;
  // Yetkazish (kuryer)
  final String? courierId;
  final String? deliveryStatus; // assigned | picked | delivered
  final double? shopLat;
  final double? shopLon;
  // Xaridor manzili va yetkazish tafsilotlari
  final String address;
  final double? lat; // xaridor joylashuvi
  final double? lon;
  final int? deliveryFee; // kuryer tarifi bo'yicha yetkazish haqi, so'm
  final double? routeKm; // do'kondan xaridorgacha taxminiy yo'l, km
  final String courierName;
  final String courierPhone;

  /// Haydovchi haqida xaridor ko'radigan ma'lumot: rasmi, mashinasi, raqami
  final String? courierPhoto;
  final String? courierCarPhoto;
  final String courierPlate;
  final DateTime? pickedAt;
  final DateTime? deliveredAt;

  Order({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.productName,
    required this.price,
    required this.customerName,
    required this.phone,
    required this.buyerLink,
    this.items = const [],
    this.shopName = '',
    this.shopPhone = '',
    this.courierId,
    this.deliveryStatus,
    this.shopLat,
    this.shopLon,
    this.address = '',
    this.lat,
    this.lon,
    this.deliveryFee,
    this.routeKm,
    this.courierName = '',
    this.courierPhone = '',
    this.courierPhoto,
    this.courierCarPhoto,
    this.courierPlate = '',
    this.pickedAt,
    this.deliveredAt,
  });

  bool get hasLocation => lat != null && lon != null;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] ?? j['_id'] ?? '',
        status: j['status'] ?? 'new',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        productName: j['productName'] ?? '',
        price: ((j['price'] ?? 0) as num).round(),
        customerName: j['customerName'] ?? '',
        phone: j['phone'] ?? '',
        buyerLink: j['buyerLink'] ?? '',
        items: ((j['items'] ?? const []) as List).map((e) => OrderItem.fromJson(e)).toList(),
        shopName: j['shopName'] ?? '',
        shopPhone: j['shopPhone'] ?? '',
        courierId: j['courierId'],
        deliveryStatus: j['deliveryStatus'],
        shopLat: (j['shopLocation'] is Map ? (j['shopLocation']['lat'] as num?) : null)?.toDouble(),
        shopLon: (j['shopLocation'] is Map ? (j['shopLocation']['lon'] as num?) : null)?.toDouble(),
        address: j['address'] ?? '',
        lat: (j['location'] is Map ? (j['location']['lat'] as num?) : null)?.toDouble(),
        lon: (j['location'] is Map ? (j['location']['lon'] as num?) : null)?.toDouble(),
        deliveryFee: (j['deliveryFee'] as num?)?.round(),
        routeKm: (j['routeKm'] as num?)?.toDouble(),
        courierName: j['courierName'] ?? '',
        courierPhone: j['courierPhone'] ?? '',
        courierPhoto: j['courierPhoto'],
        courierCarPhoto: j['courierCarPhoto'],
        courierPlate: j['courierPlate'] ?? '',
        pickedAt: DateTime.tryParse(j['pickedAt'] ?? ''),
        deliveredAt: DateTime.tryParse(j['deliveredAt'] ?? ''),
      );

  String get statusLabel => const {'new': 'Yangi', 'done': 'Bajarildi', 'cancelled': 'Bekor'}[status] ?? status;
}

/// Kuryer (yetkazib beruvchi)
class Courier {
  final String id;
  final String type; // courier | cargo
  final String name;
  final String phone;
  final String email;
  final String region;
  final String plate;
  final String? photo;

  /// Mashina rasmi — xaridor buyurtmani kim olib kelayotganini ko'radi
  final String? carPhoto;
  final String vehicle; // foot | bike | moto | car
  final String vehicleType; // yuk: labo | damas | gazel | isuzu | fura
  final int capacityKg;
  final List<String> regions;
  final int pricePerKm;
  final int basePrice;
  final String about;
  final bool online;
  final double? lat;
  final double? lon;
  final int deliveries;
  final double rating;
  final double? distanceKm;
  final int? estimatedPrice; // yuk tashuvchi: tanlangan yo'nalish uchun taxminiy narx, so'm
  final double? routeKm; // yuk tashuvchi: yo'nalish masofasi, km
  Courier({required this.id, this.type = 'courier', required this.name, required this.phone, this.email = '', this.region = '', this.plate = '', this.photo, this.carPhoto, this.vehicle = 'foot', this.vehicleType = '', this.capacityKg = 0, this.regions = const [], this.pricePerKm = 0, this.basePrice = 0, this.about = '', this.online = false, this.lat, this.lon, this.deliveries = 0, this.rating = 5, this.distanceKm, this.estimatedPrice, this.routeKm});
  bool get isCargo => type == 'cargo';
  bool get hasTariff => basePrice > 0 || pricePerKm > 0;

  factory Courier.fromJson(Map<String, dynamic> j) {
    final loc = j['location'];
    return Courier(
      id: j['id'] ?? '',
      type: j['type'] ?? 'courier',
      name: j['name'] ?? '',
      phone: j['phone'] ?? '',
      email: j['email'] ?? '',
      region: j['region'] ?? '',
      plate: j['plate'] ?? '',
      photo: j['photo'],
      carPhoto: j['carPhoto'],
      vehicle: j['vehicle'] ?? 'foot',
      vehicleType: j['vehicleType'] ?? '',
      capacityKg: (j['capacityKg'] as num?)?.toInt() ?? 0,
      regions: ((j['regions'] ?? const []) as List).map((e) => e.toString()).toList(),
      pricePerKm: (j['pricePerKm'] as num?)?.toInt() ?? 0,
      basePrice: (j['basePrice'] as num?)?.toInt() ?? 0,
      about: j['about'] ?? '',
      online: j['online'] == true,
      lat: loc is Map ? (loc['lat'] as num?)?.toDouble() : null,
      lon: loc is Map ? (loc['lon'] as num?)?.toDouble() : null,
      deliveries: (j['deliveries'] as num?)?.toInt() ?? 0,
      rating: (j['rating'] as num?)?.toDouble() ?? 5,
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      estimatedPrice: (j['estimatedPrice'] as num?)?.round(),
      routeKm: (j['routeKm'] as num?)?.toDouble(),
    );
  }

  Courier copyWith({bool? online, double? lat, double? lon, int? deliveries}) => Courier(id: id, type: type, name: name, phone: phone, email: email, region: region, plate: plate, photo: photo, carPhoto: carPhoto, vehicle: vehicle, vehicleType: vehicleType, capacityKg: capacityKg, regions: regions, pricePerKm: pricePerKm, basePrice: basePrice, about: about, online: online ?? this.online, lat: lat ?? this.lat, lon: lon ?? this.lon, deliveries: deliveries ?? this.deliveries, rating: rating, distanceKm: distanceKm, estimatedPrice: estimatedPrice, routeKm: routeKm);
}

/// Viloyatlararo yuk buyurtmasi
class CargoOrder {
  final String id;
  final String status; // new | accepted | done | rejected
  final String kind; // cargo (viloyatlararo) | direct (kuryerga to'g'ridan-to'g'ri so'rov)
  final String fromRegion;
  final String toRegion;
  final String date;
  final String cargo;
  final int weightKg;
  final String customerName;
  final String phone;
  final String address;
  final String carrierName;
  final String carrierPhone;

  /// Yukni kim olib ketishi: haydovchi rasmi, mashina rasmi va davlat raqami
  final String? carrierPhoto;
  final String? carrierCarPhoto;
  final String carrierPlate;
  final DateTime createdAt;
  final int? price; // kelishilgan narx, so'm
  final double? distanceKm; // viloyat markazlari orasidagi taxminiy yo'l
  final int? suggestedPrice; // tashuvchi tarifi bo'yicha tavsiya narx
  final DateTime? acceptedAt;
  final DateTime? doneAt;
  CargoOrder({required this.id, required this.status, this.kind = 'cargo', required this.fromRegion, required this.toRegion, this.date = '', this.cargo = '', this.weightKg = 0, this.customerName = '', this.phone = '', this.address = '', this.carrierName = '', this.carrierPhone = '', this.carrierPhoto, this.carrierCarPhoto, this.carrierPlate = '', required this.createdAt, this.price, this.distanceKm, this.suggestedPrice, this.acceptedAt, this.doneAt});
  factory CargoOrder.fromJson(Map<String, dynamic> j) => CargoOrder(
        id: j['id'] ?? j['_id'] ?? '',
        status: j['status'] ?? 'new',
        kind: j['kind'] ?? 'cargo',
        fromRegion: j['fromRegion'] ?? '',
        toRegion: j['toRegion'] ?? '',
        date: j['date'] ?? '',
        cargo: j['cargo'] ?? '',
        weightKg: (j['weightKg'] as num?)?.toInt() ?? 0,
        customerName: j['customerName'] ?? '',
        phone: j['phone'] ?? '',
        address: j['address'] ?? '',
        carrierName: j['carrierName'] ?? '',
        carrierPhone: j['carrierPhone'] ?? '',
        carrierPhoto: j['carrierPhoto'],
        carrierCarPhoto: j['carrierCarPhoto'],
        carrierPlate: j['carrierPlate'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        price: (j['price'] as num?)?.round(),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        suggestedPrice: (j['suggestedPrice'] as num?)?.round(),
        acceptedAt: DateTime.tryParse(j['acceptedAt'] ?? ''),
        doneAt: DateTime.tryParse(j['doneAt'] ?? ''),
      );
}

class Tip {
  final String type;
  final String title;
  final String text;
  Tip({required this.type, required this.title, required this.text});
  factory Tip.fromJson(Map<String, dynamic> j) => Tip(type: j['type'] ?? 'idea', title: j['title'] ?? '', text: j['text'] ?? '');
}

class Notif {
  final String id;
  final String type;
  final String title;
  final String text;
  final bool read;
  final DateTime createdAt;
  final String? mapUrl;
  Notif({required this.id, required this.type, required this.title, required this.text, required this.read, required this.createdAt, this.mapUrl});
  factory Notif.fromJson(Map<String, dynamic> j) => Notif(
        id: j['id'] ?? j['_id'] ?? '',
        type: j['type'] ?? '',
        title: j['title'] ?? '',
        text: j['text'] ?? '',
        read: j['read'] == true,
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
        mapUrl: j['meta'] is Map ? j['meta']['mapUrl'] : null,
      );
}

/// 6500000 -> "6 500 000"
String fmtPrice(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
