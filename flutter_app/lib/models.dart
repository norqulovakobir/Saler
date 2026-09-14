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
  });

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
  });

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
  final String? photo;
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
  Courier({required this.id, this.type = 'courier', required this.name, required this.phone, this.email = '', this.photo, this.vehicle = 'foot', this.vehicleType = '', this.capacityKg = 0, this.regions = const [], this.pricePerKm = 0, this.basePrice = 0, this.about = '', this.online = false, this.lat, this.lon, this.deliveries = 0, this.rating = 5, this.distanceKm});
  bool get isCargo => type == 'cargo';

  factory Courier.fromJson(Map<String, dynamic> j) {
    final loc = j['location'];
    return Courier(
      id: j['id'] ?? '',
      type: j['type'] ?? 'courier',
      name: j['name'] ?? '',
      phone: j['phone'] ?? '',
      email: j['email'] ?? '',
      photo: j['photo'],
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
    );
  }

  Courier copyWith({bool? online, double? lat, double? lon, int? deliveries}) => Courier(id: id, type: type, name: name, phone: phone, email: email, photo: photo, vehicle: vehicle, vehicleType: vehicleType, capacityKg: capacityKg, regions: regions, pricePerKm: pricePerKm, basePrice: basePrice, about: about, online: online ?? this.online, lat: lat ?? this.lat, lon: lon ?? this.lon, deliveries: deliveries ?? this.deliveries, rating: rating, distanceKm: distanceKm);
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
  final DateTime createdAt;
  CargoOrder({required this.id, required this.status, this.kind = 'cargo', required this.fromRegion, required this.toRegion, this.date = '', this.cargo = '', this.weightKg = 0, this.customerName = '', this.phone = '', this.address = '', this.carrierName = '', this.carrierPhone = '', required this.createdAt});
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
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
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
