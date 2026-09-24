/// Ilova tili: o'zbek (asosiy), rus, ingliz.
/// Matnlar kodda o'zbekcha yoziladi, `tr()` tanlangan tilga tarjima qiladi;
/// lug'atda yo'q matn o'zbekcha qoladi.
enum AppLang { uz, ru, en }

class L10n {
  static AppLang lang = AppLang.uz;

  static const names = {
    AppLang.uz: "O'zbekcha",
    AppLang.ru: 'Русский',
    AppLang.en: 'English'
  };
  static const flags = {
    AppLang.uz: '🇺🇿',
    AppLang.ru: '🇷🇺',
    AppLang.en: '🇬🇧'
  };

  /// Server so'rovlari uchun til kodi
  static String get code => lang.name;

  static const Map<String, List<String>> _d = {
    // Navigatsiya
    "Do'konlar": ['Магазины', 'Shops'],
    'Xarita': ['Карта', 'Map'],
    'Chat': ['Чат', 'Chat'],
    'Buyurtmalar': ['Заказы', 'Orders'],
    'Sotuvchi': ['Продавец', 'Seller'],
    'Xizmatlar': ['Сервисы', 'Services'],
    'Analitika': ['Аналитика', 'Analytics'],
    'Buyurtma': ['Заказы', 'Orders'],
    'AI tavsiya': ['AI советы', 'AI tips'],
    'Mahsulot': ['Товары', 'Products'],
    'Ortga': ['Назад', 'Back'],
    // Kuryerga chiqadigan bildirishnoma
    'Sizga buyurtma bor': ['У вас есть заказ', 'You have an order'],
    'ta yangi buyurtma': ['новых заказа', 'new orders'],
    'Yetkazib berish': ['Доставка', 'Delivery'],
    'Yuk': ['Груз', 'Cargo'],
    // Do'kon kartochkasida: "12 mahsulot"
    'mahsulot': ['товар', 'products'],
    'Profil': ['Профиль', 'Profile'],
    'Mehmon': ['Гость', 'Guest'],
    'Mening sahifam': ['Моя страница', 'My space'],
    'Tezkor amallar': ['Быстрые действия', 'Quick actions'],
    'Bildirishnomalar': ['Уведомления', 'Notifications'],
    "Hozircha bildirishnoma yo'q": [
      'Уведомлений пока нет',
      'No notifications yet'
    ],
    "Berilgan buyurtmalar va ularning holati": [
      'Оформленные заказы и их статус',
      'Placed orders and their status'
    ],
    "Buyurtma berish uchun tizimga kiring": [
      'Войдите, чтобы оформить заказ',
      'Sign in to place an order'
    ],
    "Aloqa ma'lumotlari": ['Контактные данные', 'Contact details'],
    'Sozlamalar': ['Настройки', 'Settings'],
    // Bosh sahifa
    'Xayrli tong': ['Доброе утро', 'Good morning'],
    'Xayrli kun': ['Добрый день', 'Good afternoon'],
    'Xayrli kech': ['Добрый вечер', 'Good evening'],
    'Xaridor': ['Покупатель', 'Customer'],
    "Do'kon yoki mahsulot qidiring": [
      'Поиск магазина или товара',
      'Search shops or products'
    ],
    'SOFIA · AI YORDAMCHI': ['SOFIA · AI ПОМОЩНИК', 'SOFIA · AI ASSISTANT'],
    "Nima kerakligini yozing — Sofia do'kon topib beradi": [
      'Напишите, что нужно — Sofia найдёт магазин',
      'Tell Sofia what you need and she will find a shop'
    ],
    'Chatni boshlash': ['Начать чат', 'Start chat'],
    'Xaritada': ['На карте', 'On map'],
    "Do'kon topilmadi": ['Магазины не найдены', 'No shops found'],
    "Serverga ulanib bo'lmadi": [
      'Нет связи с сервером',
      'Could not reach the server'
    ],
    'Qayta urinish': ['Повторить', 'Retry'],
    'Mavzu': ['Тема', 'Theme'],
    'Avtomatik': ['Авто', 'Auto'],
    "Yorug'": ['Светлая', 'Light'],
    "Qorong'i": ['Тёмная', 'Dark'],
    'Til': ['Язык', 'Language'],
    'Ilova tili': ['Язык приложения', 'App language'],
    "O'tkazib yuborish": ['Пропустить', 'Skip'],
    'Keyingisi': ['Далее', 'Next'],
    'Tilni tanlang': ['Выберите язык', 'Choose language'],
    // Do'kon sahifasi
    'Qidirish': ['Поиск', 'Search'],
    'Yangi': ['Новые', 'New'],
    'Arzon': ['Дешевле', 'Cheap'],
    'Qimmat': ['Дороже', 'Expensive'],
    'Mashhur': ['Популярные', 'Popular'],
    'Topilmadi': ['Ничего не найдено', 'Nothing found'],
    'onlayn': ['онлайн', 'online'],
    'ta mahsulot': ['товаров', 'products'],
    'ta sotuv': ['продаж', 'sales'],
    'bilan chat': ['— чат', '— chat'],
    "Savatchaga qo'shildi": ['Добавлено в корзину', 'Added to cart'],
    "Savatchada boshqa do'kon mahsuloti bor": [
      'В корзине товар другого магазина',
      'Your cart has items from another shop'
    ],
    "Tozalab, shu do'kondan boshlaymizmi?": [
      'Очистить и начать с этого магазина?',
      'Clear it and start with this shop?'
    ],
    'Ha, tozalash': ['Да, очистить', 'Yes, clear'],
    'Bekor qilish': ['Отмена', 'Cancel'],
    'Ha': ['Да', 'Yes'],
    // Mahsulot
    'Sotib olish': ['Купить', 'Buy'],
    "Sotuvchi · savolingiz bo'lsa yozing": [
      'Продавец · напишите, если есть вопрос',
      'Seller · ask if you have a question'
    ],
    'haqida batafsil aytib bering': [
      '— расскажите подробнее',
      '— tell me more about it'
    ],
    // Savatcha / buyurtma
    'Savatcha': ['Корзина', 'Cart'],
    "Savatcha bo'sh": ['Корзина пуста', 'Cart is empty'],
    'Tozalash': ['Очистить', 'Clear'],
    'Jami': ['Итого', 'Total'],
    'Buyurtma berish': ['Оформить заказ', 'Place order'],
    'Ismingiz': ['Ваше имя', 'Your name'],
    'Telefon raqam': ['Номер телефона', 'Phone number'],
    'Buyurtma qabul qilindi!': ['Заказ принят!', 'Order received!'],
    "Sotuvchi tez orada siz bilan bog'lanadi.": [
      'Продавец скоро свяжется с вами.',
      'The seller will contact you soon.'
    ],
    "Sotuvchi tez orada siz bilan bog'lanadi": [
      'Продавец скоро свяжется с вами',
      'The seller will contact you soon'
    ],
    'Yopish': ['Закрыть', 'Close'],
    'Buyurtmalarim': ['Мои заказы', 'My orders'],
    "Hozircha buyurtma yo'q": ['Заказов пока нет', 'No orders yet'],
    "Do'konga qo'ng'iroq": ['Позвонить в магазин', 'Call the shop'],
    // Sevimlilar
    'Sevimlilar': ['Избранное', 'Favorites'],
    "Sevimlilar bo'sh\nMahsulot ustidagi yurakchani bosing": [
      'Избранное пусто\nНажмите сердечко на товаре',
      'No favorites yet\nTap the heart on a product'
    ],
    // Xarita
    "Do'konlar xaritasi": ['Карта магазинов', 'Shops map'],
    'Men qayerdaman': ['Где я', 'Where am I'],
    'Joylashuvga ruxsat berilmadi': [
      'Нет доступа к геолокации',
      'Location permission denied'
    ],
    "Joylashuv xizmati o'chiq. Sozlamalardan yoqing.": [
      'Геолокация выключена. Включите в настройках.',
      'Location services are off. Enable them in settings.'
    ],
    "Do'konga kirish": ['Открыть магазин', 'Open shop'],
    "ta do'kon": ['магазинов', 'shops'],
    'Xarita turi': ['Тип карты', 'Map type'],
    'Oddiy': ['Обычная', 'Standard'],
    'Sputnik': ['Спутник', 'Satellite'],
    'Gibrid': ['Гибрид', 'Hybrid'],
    "Yo'nalishni boshlash": ['Построить маршрут', 'Start route'],
    "Yo'nalish": ['Маршрут', 'Route'],
    "Yo'nalish hisoblanmoqda...": ['Строим маршрут...', 'Calculating route...'],
    'Marshrut topilmadi': ['Маршрут не найден', 'Route not found'],
    'Mashina': ['На машине', 'Driving'],
    'Piyoda': ['Пешком', 'Walking'],
    'Navigator': ['Навигатор', 'Navigator'],
    "Do'kon": ['Магазин', 'Shop'],
    'daqiqa': ['мин', 'min'],
    'soat': ['ч', 'h'],
    // Navigatsiya
    'Boshlash': ['Начать', 'Start'],
    'Tugatish': ['Завершить', 'Finish'],
    "Yo'lga chiqing": ['Начинайте движение', 'Start moving'],
    'Manzilga yetib keldingiz': ['Вы прибыли', 'You have arrived'],
    "Aylanma yo'lda": ['На кольце', 'At the roundabout'],
    'chiqishdan chiqing': ['съезд', 'exit'],
    "Aylanma yo'lga kiring": ['Въезжайте на кольцо', 'Enter the roundabout'],
    "Yo'lga qo'shiling": ['Перестройтесь', 'Merge'],
    "Yo'ldan chiqing": ['Съезжайте', 'Take the exit'],
    "Chapdagi yo'lni tanlang": ['Держитесь левее', 'Keep left'],
    "O'ngdagi yo'lni tanlang": ['Держитесь правее', 'Keep right'],
    "Yo'l oxirida chapga buriling": [
      'В конце дороги поверните налево',
      'At the end of the road turn left'
    ],
    "Yo'l oxirida o'ngga buriling": [
      'В конце дороги поверните направо',
      'At the end of the road turn right'
    ],
    'Chapga buriling': ['Поверните налево', 'Turn left'],
    "O'ngga buriling": ['Поверните направо', 'Turn right'],
    'Biroz chapga': ['Немного левее', 'Slight left'],
    "Biroz o'ngga": ['Немного правее', 'Slight right'],
    'Keskin chapga buriling': ['Резко налево', 'Sharp left'],
    "Keskin o'ngga buriling": ['Резко направо', 'Sharp right'],
    'Orqaga qayting': ['Развернитесь', 'Make a U-turn'],
    "To'g'ri yuring": ['Двигайтесь прямо', 'Go straight'],
    // Kuryer
    'Kuryer': ['Курьер', 'Courier'],
    'kuryer': ['курьер', 'courier'],
    'Kuryer yollash': ['Вызвать курьера', 'Hire a courier'],
    'Kuryerni yollash': ['Вызвать курьера', 'Hire courier'],
    'Yetkazish': ['Доставка', 'Deliveries'],
    'Onlayn': ['Онлайн', 'Online'],
    'Oflayn': ['Оффлайн', 'Offline'],
    'Velosiped': ['Велосипед', 'Bicycle'],
    'Mototsikl': ['Мотоцикл', 'Motorbike'],
    'Ism-sharif': ['ФИО', 'Full name'],
    'Ism': ['Имя', 'Name'],
    'KURYER': ['КУРЬЕР', 'COURIER'],
    'TRANSPORT': ['ТРАНСПОРТ', 'VEHICLE'],
    "Kuryer bo'ling": ['Станьте курьером', 'Become a courier'],
    'Kuryer kirishi': ['Вход курьера', 'Courier sign in'],
    'Buyurtmani oldim': ['Забрал заказ', 'Picked up'],
    'Yetkazdim': ['Доставил', 'Delivered'],
    'Yetkazildi': ['Доставлено', 'Delivered'],
    'Rad etish': ['Отклонить', 'Decline'],
    'Faol': ['Активные', 'Active'],
    'Yetkazilgan': ['Доставленные', 'Delivered'],
    "Yo'lda": ['В пути', 'On the way'],
    'Profilni tahrirlash': ['Редактировать профиль', 'Edit profile'],
    'Saqlash': ['Сохранить', 'Save'],
    'Reyting': ['Рейтинг', 'Rating'],
    'Holat': ['Статус', 'Status'],
    'yetkazish': ['доставок', 'deliveries'],
    'ta kuryer onlayn': ['курьеров онлайн', 'couriers online'],
    'Kuryerlar qidirilmoqda...': ['Ищем курьеров...', 'Finding couriers...'],
    'Kuryer yollandi!': ['Курьер вызван!', 'Courier hired!'],
    'Qaysi buyurtmani yetkazsin?': [
      'Какой заказ доставить?',
      'Which order to deliver?'
    ],
    'Siz onlaynsiz': ['Вы онлайн', 'You are online'],
    'Siz oflaynsiz': ['Вы оффлайн', 'You are offline'],
    // Yuk tashuvchi
    'Yuk tashuvchi': ['Грузоперевозчик', 'Cargo carrier'],
    'yuk tashuvchi': ['грузоперевозчик', 'cargo carrier'],
    'Boshqa': ['Другое', 'Other'],
    'Yuklar': ['Грузы', 'Cargo'],
    'Yuk mashinasi': ['Грузовик', 'Truck'],
    'Yuk mashinasi buyurtma qilish': ['Заказать грузовик', 'Book a truck'],
    'Viloyatlararo yuk': ['Межобластные грузы', 'Intercity cargo'],
    'Qayerdan': ['Откуда', 'From'],
    'Qayerga': ['Куда', 'To'],
    'Barchasi': ['Все', 'All'],
    'Tashuvchilar': ['Перевозчики', 'Carriers'],
    'Mening yuk buyurtmalarim': ['Мои грузовые заказы', 'My cargo orders'],
    'Mashina buyurtma qilish': ['Заказать машину', 'Book vehicle'],
    'Qabul qilindi': ['Принято', 'Accepted'],
    'Qabul qilish': ['Принять', 'Accept'],
    'Kutilmoqda': ['Ожидание', 'Pending'],
    'Rad etildi': ['Отклонено', 'Declined'],
    'Buyurtma yuborildi!': ['Заказ отправлен!', 'Order sent!'],
    "Rasm qo'yish": ['Добавить фото', 'Add photo'],
    "Rasmni o'zgartirish": ['Изменить фото', 'Change photo'],
    'Reyslar': ['Рейсы', 'Trips'],
    'reys': ['рейсов', 'trips'],
    'dan': ['от', 'from'],
    'Sana': ['Дата', 'Date'],
    'Viloyatlarni tanlang': ['Выберите области', 'Select regions'],
    'Kamida bitta viloyatni tanlang': [
      'Выберите хотя бы одну область',
      'Select at least one region'
    ],
    "So'rov yuborish": ['Отправить запрос', 'Send request'],
    "So'rov yuborildi!": ['Запрос отправлен!', 'Request sent!'],
    "So'rovlar": ['Запросы', 'Requests'],
    "Qo'ng'iroq": ['Позвонить', 'Call'],
    'Mening joyim': ['Моё местоположение', 'My location'],
    'Qayerdan olib ketsin': ['Откуда забрать', 'Pickup from'],
    'Qayerga yetkazsin': ['Куда доставить', 'Deliver to'],
    'Nima yetkaziladi (izoh)': [
      'Что доставить (комментарий)',
      'What to deliver (note)'
    ],
    "siz bilan bog'lanadi. Telefoni": [
      'свяжется с вами. Телефон',
      'will contact you. Phone'
    ],
    'Yollash': ['Вызвать', 'Hire'],
    'Ochish': ['Открыть', 'Open'],
    'Men kuryer yollamoqchiman': [
      'Я хочу вызвать курьера',
      'I want to hire a courier'
    ],
    "Xaritada kuryerlarni ko'rish": ['Курьеры на карте', 'See couriers on map'],
    'Kategoriya': ['Категория', 'Category'],
    'Kategoriyani tanlang': ['Выберите категорию', 'Select a category'],
    "O'xshash mahsulotlar": ['Похожие товары', 'Similar products'],
    "Rasm qo'shish": ['Добавить фото', 'Add photo'],
    'Kamera': ['Камера', 'Camera'],
    'Hozir suratga olish': ['Сделать снимок сейчас', 'Take a photo now'],
    'Galereya': ['Галерея', 'Gallery'],
    'Telefondagi rasmlardan tanlash': [
      'Выбрать из фото на телефоне',
      'Choose from phone photos'
    ],
    "Rasm olib bo'lmadi": [
      'Не удалось получить фото',
      'Could not get the photo'
    ],
    "Bu kategoriyada hozircha mahsulot yo'q": [
      'В этой категории пока нет товаров',
      'No products in this category yet'
    ],
    'KATEGORIYALAR': ['КАТЕГОРИИ', 'CATEGORIES'],
    'Surib qidiring': ['Листайте', 'Swipe'],
    // Sofia
    "Assalomu alaykum! Men Sofia, Rydex yordamchisiman. Nima olmoqchisiz? Sizga mos do'konlarni topib, xaritada ko'rsataman.":
        [
      'Здравствуйте! Я Sofia, помощник Rydex. Что вы хотите купить? Я подберу подходящие магазины и покажу их на карте.',
      "Hello! I'm Sofia, the Rydex assistant. What would you like to buy? I'll find matching shops and show them on the map.",
    ],
    "AI yordamchi · do'kon topib tavsiya beradi": [
      'AI помощник · подбирает магазины',
      'AI assistant · recommends shops'
    ],
    'Nima olmoqchisiz?': [
      'Что вы хотите купить?',
      'What would you like to buy?'
    ],
    "Yaqin atrofdagi do'konlar": ['Магазины рядом', 'Shops nearby'],
    "Yaqin atrofimdagi do'konlarni ko'rsating": [
      'Покажите магазины рядом со мной',
      'Show me shops near me'
    ],
    'Kiyim olmoqchiman': ['Хочу купить одежду', 'I want to buy clothes'],
    'Men kiyim olmoqchiman': ['Я хочу купить одежду', 'I want to buy clothes'],
    'Telefon kerak': ['Нужен телефон', 'Need a phone'],
    'Menga telefon kerak': ['Мне нужен телефон', 'I need a phone'],
    'Oziq-ovqat': ['Продукты', 'Groceries'],
    "Oziq-ovqat do'konlari bormi?": [
      'Есть продуктовые магазины?',
      'Are there grocery shops?'
    ],
    "Hammasini xaritada ko'rish": ['Показать все на карте', 'Show all on map'],
    'Suhbatni tozalaysizmi?': [
      'Очистить переписку?',
      'Clear the conversation?'
    ],
    'Yordamchi suhbatni boshidan boshlaydi.': [
      'Помощник начнёт разговор заново.',
      'The assistant will start over.'
    ],
    "Bu do'konlarning joylashuvi ko'rsatilmagan": [
      'У этих магазинов не указано местоположение',
      'These shops have no location set'
    ],
    "Hozir javob bera olmayapman, birozdan so'ng urinib ko'ring.": [
      'Сейчас не могу ответить, попробуйте чуть позже.',
      "I can't answer right now, please try again shortly."
    ],
    // Sotuvchi chati
    'Xabar yozing...': ['Напишите сообщение...', 'Type a message...'],
    'Eng arzoni?': ['Самое дешёвое?', 'Cheapest?'],
    'Eng arzoni qaysi?': ['Что самое дешёвое?', 'Which is the cheapest?'],
    'Yetkazib berish bormi?': ['Есть доставка?', 'Do you deliver?'],
    "Mahsulotlarni ko'rsating": ['Покажите товары', 'Show products'],
    "Sizda qanday mahsulotlar bor? Ko'rsating.": [
      'Какие у вас есть товары? Покажите.',
      'What products do you have? Show me.'
    ],
    'sotuvchisi · onlayn': ['· продавец онлайн', '· seller online'],
    'Suhbat tarixini tozalaysizmi?': [
      'Очистить историю чата?',
      'Clear chat history?'
    ],
    "Yozishmalar o'chiriladi, sotuvchi suhbatni boshidan boshlaydi.": [
      'Переписка будет удалена, продавец начнёт заново.',
      'Messages will be deleted and the seller will start over.'
    ],
    'Suhbat tozalandi': ['Чат очищен', 'Chat cleared'],
    'Assalomu alaykum! Xush kelibsiz, sizga nima kerak edi?': [
      'Здравствуйте! Добро пожаловать, что вам нужно?',
      'Hello! Welcome, what are you looking for?'
    ],
    // Sotuvchi kirish
    "Do'koningizni oching": ['Откройте свой магазин', 'Open your shop'],
    'AI sotuvchi mijozlar bilan 24/7 gaplashadi, buyurtmalarni qabul qiladi va sizga xabar beradi.':
        [
      'AI-продавец общается с клиентами 24/7, принимает заказы и уведомляет вас.',
      'The AI seller talks to customers 24/7, takes orders and notifies you.'
    ],
    'AI sotuvchi': ['AI продавец', 'AI seller'],
    "Mahsulotlaringizni biladi, savollarga o'zi javob beradi": [
      'Знает ваши товары и сам отвечает на вопросы',
      'Knows your products and answers questions'
    ],
    'Buyurtma bildirishnomalari': [
      'Уведомления о заказах',
      'Order notifications'
    ],
    'Yangi buyurtma kelganda telefoningizga xabar keladi': [
      'Новый заказ — уведомление на телефон',
      'Get notified on your phone for new orders'
    ],
    "Ko'rishlar, sotuvlar va AI tavsiyalar bir joyda": [
      'Просмотры, продажи и AI-советы в одном месте',
      'Views, sales and AI tips in one place'
    ],
    'Kirish': ['Войти', 'Sign in'],
    "Ro'yxatdan o'tish": ['Регистрация', 'Sign up'],
    "Do'kon Telegram botda ham ochilishi mumkin": [
      'Магазин можно открыть и в Telegram-боте',
      'A shop can also be opened in the Telegram bot'
    ],
    'Xush kelibsiz!': ['С возвращением!', 'Welcome back!'],
    "Do'kon oching": ['Откройте магазин', 'Open a shop'],
    'Sotuvchi paneliga kirish uchun login va parolingizni kiriting.': [
      'Введите логин и пароль для входа в панель продавца.',
      'Enter your login and password to access the seller panel.'
    ],
    "Bir daqiqada do'kon yarating — AI sotuvchi darhol ishga tushadi.": [
      'Создайте магазин за минуту — AI-продавец сразу начнёт работать.',
      'Create a shop in a minute and the AI seller starts right away.'
    ],
    "DO'KON": ['МАГАЗИН', 'SHOP'],
    "KIRISH MA'LUMOTLARI": ['ДАННЫЕ ДЛЯ ВХОДА', 'LOGIN DETAILS'],
    "Do'kon nomi": ['Название магазина', 'Shop name'],
    'Egasining ism-sharifi': ['ФИО владельца', 'Owner full name'],
    'Sotuvchi ismi': ['Имя продавца', 'Seller name'],
    'AI shu nomdan gaplashadi': [
      'AI будет говорить от этого имени',
      'The AI speaks under this name'
    ],
    'Telefon': ['Телефон', 'Phone'],
    'Login': ['Логин', 'Login'],
    'Parol': ['Пароль', 'Password'],
    "Barcha maydonlarni to'ldiring": [
      'Заполните все поля',
      'Fill in all fields'
    ],
    "Do'kon yaratish": ['Создать магазин', 'Create shop'],
    'Akkauntingiz bormi? ': ['Уже есть аккаунт? ', 'Already have an account? '],
    "Akkauntingiz yo'qmi? ": ['Нет аккаунта? ', "Don't have an account? "],
    // Reyting
    "Do'konlar reytingi": ['Рейтинг магазинов', 'Shop ratings'],
    "Eng yaxshi do'konlar": ['Лучшие магазины', 'Top shops'],
    "Reyting bajarilgan sotuvlar soniga qarab o'sadi": [
      'Рейтинг растёт с количеством выполненных продаж',
      'Rating grows with completed sales'
    ],
    "Hozircha do'kon yo'q": ['Магазинов пока нет', 'No shops yet'],
    'Darajalar: Yangi · Bronza (1+) · Kumush (5+) · Oltin (15+) · Platina (30+ sotuv)':
        [
      'Уровни: Новый · Бронза (1+) · Серебро (5+) · Золото (15+) · Платина (30+ продаж)',
      'Levels: New · Bronze (1+) · Silver (5+) · Gold (15+) · Platinum (30+ sales)'
    ],
    'Yangi_lvl': ['Новый', 'New'],
    'Bronza': ['Бронза', 'Bronze'],
    'Kumush': ['Серебро', 'Silver'],
    'Oltin': ['Золото', 'Gold'],
    'Platina': ['Платина', 'Platinum'],
    // Sotuvchi profil
    'Logo yuklash': ['Загрузить логотип', 'Upload logo'],
    "Logoni o'zgartirish": ['Изменить логотип', 'Change logo'],
    "Do'kon sozlamalari": ['Настройки магазина', 'Shop settings'],
    "Do'kon joylashuvi": ['Местоположение магазина', 'Shop location'],
    'Xaridor rejimi': ['Режим покупателя', 'Customer mode'],
    'Chiqish': ['Выйти', 'Sign out'],
    // Rol tanlash, ro'yxatdan o'tish va tasdiqlash
    "Kim bo'lib davom etasiz?": ['Кем вы будете?', 'How will you continue?'],
    "Yonga suring va o'zingizga mos bo'limni tanlang": [
      'Листайте и выберите подходящий раздел',
      'Swipe and pick the option that fits you'
    ],
    "Hozircha shunchaki ko'rib chiqaman": [
      'Пока просто посмотрю',
      'Just browsing for now'
    ],
    'Xarid qilishni boshlash': ['Начать покупки', 'Start shopping'],
    'Hisobim bor — Kirish': [
      'У меня есть аккаунт — Войти',
      'I have an account — Sign in'
    ],
    'Buyurtma berishda email orqali tasdiqlaysiz': [
      'Подтвердите по email при заказе',
      'You confirm by email when ordering'
    ],
    "Do'konlarni ko'ring, Reels'dan mahsulot tanlang va buyurtma bering": [
      'Смотрите магазины, выбирайте товары в Reels и заказывайте',
      'Browse shops, pick products in Reels and order'
    ],
    "Minglab do'kon va mahsulot": [
      'Тысячи магазинов и товаров',
      'Thousands of shops and products'
    ],
    'Reels: siz uchun tanlangan mahsulotlar': [
      'Reels: товары, подобранные для вас',
      'Reels: products picked for you'
    ],
    'AI sotuvchi bilan suhbat': [
      'Чат с AI-продавцом',
      'Chat with the AI seller'
    ],
    "Do'kon oching — AI sotuvchi mijozlar bilan 24/7 gaplashadi": [
      'Откройте магазин — AI-продавец общается с клиентами 24/7',
      'Open a shop — the AI seller talks to customers 24/7'
    ],
    'AI sotuvchi va avtomatik javoblar': [
      'AI-продавец и автоответы',
      'AI seller and automatic replies'
    ],
    'Buyurtmalar, analitika va hisobotlar': [
      'Заказы, аналитика и отчёты',
      'Orders, analytics and reports'
    ],
    "Obunachilarga yangi mahsulot darhol ko'rinadi": [
      'Подписчики сразу видят новый товар',
      'Followers see new products first'
    ],
    'Buyurtmalarni yetkazing va daromad qiling': [
      'Доставляйте заказы и зарабатывайте',
      'Deliver orders and earn'
    ],
    'Yaqin buyurtmalar avtomatik biriktiriladi': [
      'Ближайшие заказы назначаются автоматически',
      'Nearby orders are assigned automatically'
    ],
    'Marshrut rejasi va navigatsiya': [
      'План маршрута и навигация',
      'Route plan and navigation'
    ],
    'Daromad statistikasi va AI maslahatlar': [
      'Статистика дохода и AI-советы',
      'Earnings stats and AI tips'
    ],
    'Viloyatlararo yuk tashing — mijozlar sizni topadi': [
      'Перевозите грузы между регионами — клиенты вас найдут',
      'Carry cargo between regions — customers will find you'
    ],
    "Yo'nalish va tarif bo'yicha narx": [
      'Цена по маршруту и тарифу',
      'Price by route and tariff'
    ],
    'Buyurtmalar va daromad hisobi': [
      'Заказы и учёт дохода',
      'Orders and earnings'
    ],
    "Shaxsiy ma'lumotlar": ['Личные данные', 'Personal details'],
    'Familiya': ['Фамилия', 'Last name'],
    'Ismingizni kiriting': ['Введите имя', 'Enter your first name'],
    'Familiyangizni kiriting': ['Введите фамилию', 'Enter your last name'],
    'Telefon raqami': ['Номер телефона', 'Phone number'],
    "Telefon raqamini to'liq kiriting": [
      'Введите номер телефона полностью',
      'Enter the full phone number'
    ],
    "Email manzilini to'g'ri kiriting": [
      'Введите корректный email',
      'Enter a valid email address'
    ],
    'Tasdiqlash kodi shu emailga yuboriladi': [
      'Код подтверждения придёт на этот email',
      'The confirmation code goes to this email'
    ],
    "Do'kon nomini kiriting": [
      'Введите название магазина',
      'Enter the shop name'
    ],
    'Masalan: Alidev Market': [
      'Например: Alidev Market',
      'For example: Alidev Market'
    ],
    'AI sotuvchi ismi': ['Имя AI-продавца', 'AI seller name'],
    "Bo'sh qoldirsangiz — Madina": [
      'Если оставить пустым — Madina',
      'Leave empty for Madina'
    ],
    'Mijozlar bilan shu ismdan gaplashadi': [
      'Под этим именем общается с клиентами',
      'It talks to customers under this name'
    ],
    'Logo': ['Логотип', 'Logo'],
    "Ixtiyoriy — keyin ham qo'shsa bo'ladi": [
      'Необязательно — можно добавить позже',
      'Optional — you can add it later'
    ],
    "O'zgartirish": ['Изменить', 'Change'],
    'Qayerda yashaysiz': ['Где вы живёте', 'Where you live'],
    'Viloyat': ['Регион', 'Region'],
    'Viloyatni tanlang': ['Выберите регион', 'Choose a region'],
    'Tanlanmagan': ['Не выбрано', 'Not selected'],
    "Xaritada do'koningiz turgan joyni bosing": [
      'Отметьте на карте, где находится магазин',
      'Tap the map where your shop is'
    ],
    "Do'kon joyini xaritada belgilang": [
      'Отметьте магазин на карте',
      'Mark the shop on the map'
    ],
    'Manzil': ['Адрес', 'Address'],
    'Manzilni kiriting': ['Введите адрес', 'Enter the address'],
    'Masalan: Chorsu bozori, 2-qator': [
      'Например: рынок Чорсу, 2-й ряд',
      'For example: Chorsu bazaar, row 2'
    ],
    "Joylashuvni aniqlab bo'lmadi. Xaritada qo'lda belgilang": [
      'Не удалось определить местоположение. Отметьте вручную',
      'Could not detect the location. Mark it manually'
    ],
    'Transport': ['Транспорт', 'Vehicle'],
    'Davlat raqami': ['Гос. номер', 'Plate number'],
    'Mashina davlat raqamini kiriting': [
      'Введите гос. номер машины',
      'Enter the vehicle plate number'
    ],
    'Ish viloyati': ['Регион работы', 'Working region'],
    'Ishlaydigan viloyatingizni tanlang': [
      'Выберите регион работы',
      'Choose your working region'
    ],
    'Rasm': ['Фото', 'Photo'],
    'Ixtiyoriy — xaridorlar sizni tanishi uchun': [
      'Необязательно — чтобы покупатели вас узнавали',
      'Optional — so buyers recognise you'
    ],
    "Rasmni yuklab bo'lmadi": [
      'Не удалось загрузить фото',
      'Could not upload the photo'
    ],
    "Sig'im, kg": ['Вместимость, кг', 'Capacity, kg'],
    "Yuk sig'imini kiriting (kg)": [
      'Введите вместимость (кг)',
      'Enter the load capacity (kg)'
    ],
    'Tarif': ['Тариф', 'Tariff'],
    "Boshlang'ich narx, so'm": ['Начальная цена, сум', 'Base price, soum'],
    "1 km narxi, so'm": ['Цена за 1 км, сум', 'Price per km, soum'],
    "Narxni kiriting: boshlang'ich narx yoki 1 km narxi": [
      'Укажите цену: начальную или за 1 км',
      'Enter a price: base or per km'
    ],
    "Mijozga narx shu tarif bo'yicha taxminan hisoblanadi": [
      'Клиенту цена считается по этому тарифу',
      'The customer price is estimated from this tariff'
    ],
    'Xizmat viloyatlari': ['Регионы обслуживания', 'Service regions'],
    "Kirish ma'lumotlari": ['Данные для входа', 'Sign-in details'],
    'lotin harflari va raqamlar': [
      'латиница и цифры',
      'latin letters and digits'
    ],
    'Login 3–30 belgi: lotin harflari, raqam, _ yoki .': [
      'Логин 3–30 символов: латиница, цифры, _ или .',
      'Login 3–30 chars: latin letters, digits, _ or .'
    ],
    'Parolni takrorlang': ['Повторите пароль', 'Repeat the password'],
    'Parollar mos kelmadi': ['Пароли не совпадают', 'Passwords do not match'],
    'Keyingisi ': ['Далее', 'Next'],
    'Hisob yaratish': ['Создать аккаунт', 'Create account'],
    'Tugmani bosgach, emailingizga 6 xonali kod yuboriladi': [
      'После нажатия на email придёт 6-значный код',
      'After you tap, a 6-digit code goes to your email'
    ],
    "Ma'lumotlar xavfsiz saqlanadi": [
      'Данные хранятся безопасно',
      'Your details are stored securely'
    ],
    'Emailni tasdiqlang': ['Подтвердите email', 'Confirm your email'],
    'Hisob kod tasdiqlangandan keyin yaratiladi': [
      'Аккаунт создаётся после подтверждения кода',
      'The account is created after the code is confirmed'
    ],
    'Kod yuborildi': ['Код отправлен', 'Code sent'],
    'Kod': ['Код', 'Code'],
    '6 xonali kodni kiriting': [
      'Введите 6-значный код',
      'Enter the 6-digit code'
    ],
    'Kodni qayta yuborish': ['Отправить код снова', 'Resend the code'],
    'Kodni olish': ['Получить код', 'Get the code'],
    'Test rejimi: email xizmati sozlanmagan': [
      'Тестовый режим: email не настроен',
      'Test mode: email service not configured'
    ],
    'Emailingizga yuborilgan 6 xonali kodni kiriting': [
      'Введите 6-значный код из письма',
      'Enter the 6-digit code from the email'
    ],
    'Tasdiqlash': ['Подтвердить', 'Confirm'],
    'Tasdiqlangan': ['Подтверждён', 'Verified'],
    'Sotuvchi kirishi': ['Вход для продавца', 'Seller sign-in'],
    'Yuk tashuvchi kirishi': ['Вход для перевозчика', 'Carrier sign-in'],
    'Login yoki email va parolingizni kiriting': [
      'Введите логин или email и пароль',
      'Enter your login or email and password'
    ],
    'Login yoki email': ['Логин или email', 'Login or email'],
    'Login va parolni kiriting': [
      'Введите логин и пароль',
      'Enter the login and password'
    ],
    'Parolni unutdingizmi?': ['Забыли пароль?', 'Forgot your password?'],
    'Parolni tiklash': ['Восстановление пароля', 'Reset your password'],
    "Hisobingizga bog'langan emailni kiriting": [
      'Введите email, привязанный к аккаунту',
      'Enter the email linked to the account'
    ],
    "Emailga kelgan kodni kiriting va yangi parol qo'ying": [
      'Введите код из письма и задайте новый пароль',
      'Enter the emailed code and set a new password'
    ],
    'Yangi parol': ['Новый пароль', 'New password'],
    'Parolni yangilash': ['Обновить пароль', 'Update the password'],
    'Parol yangilandi. Endi yangi parol bilan kiring': [
      'Пароль обновлён. Войдите с новым паролем',
      'Password updated. Sign in with the new one'
    ],
    "Hisobingiz yo'qmi? Ro'yxatdan o'tish": [
      'Нет аккаунта? Зарегистрируйтесь',
      "Don't have an account? Sign up"
    ],
    'Tizimga kirish': ['Вход', 'Sign in'],
    'Ism, telefon va emailingizni kiriting — emailga 6 xonali kod yuboramiz': [
      'Введите имя, телефон и email — пришлём 6-значный код',
      'Enter your name, phone and email — we send a 6-digit code'
    ],
    'Telegram username yoki raqamingizni kiriting': [
      'Введите Telegram username или номер',
      'Enter your Telegram username or number'
    ],
    "Ma'lumotlaringiz faqat buyurtmani rasmiylashtirish uchun ishlatiladi": [
      'Данные нужны только для оформления заказа',
      'Your details are only used to place the order'
    ],
    'Buyurtma berish uchun kiring': [
      'Войдите, чтобы заказать',
      'Sign in to order'
    ],
    "Buyurtma berish uchun ma'lumotlaringizni kiriting": [
      'Введите данные для оформления заказа',
      'Enter your details to place the order'
    ],
    'Yetkazish manzili': ['Адрес доставки', 'Delivery address'],
    'Ixtiyoriy': ['Необязательно', 'Optional'],
    "Obuna bo'lish uchun kiring": [
      'Войдите, чтобы подписаться',
      'Sign in to follow'
    ],
    "Obunachilar yangi mahsulotlarni birinchi bo'lib ko'radi": [
      'Подписчики первыми видят новинки',
      'Followers see new products first'
    ],
    "Reels'ni ko'rish uchun tizimga kiring": [
      'Войдите, чтобы смотреть Reels',
      'Sign in to watch Reels'
    ],
    'Reels uchun tizimga kiring': ['Войдите для Reels', 'Sign in for Reels'],
    "Qiziqishlaringizga mos mahsulotlarni ko'rsatamiz": [
      'Покажем товары по вашим интересам',
      'We will show products that match your interests'
    ],
    "Siz mehmon sifatida ko'ryapsiz": [
      'Вы смотрите как гость',
      'You are browsing as a guest'
    ],
    'Buyurtma berish va Reels uchun tizimga kiring': [
      'Войдите, чтобы заказывать и смотреть Reels',
      'Sign in to order and watch Reels'
    ],
  };

  static String tr(String uz) {
    final v = _d[uz];
    if (v == null || lang == AppLang.uz) return uz;
    return lang == AppLang.ru ? v[0] : v[1];
  }
}

/// Qisqa yordamchi: tr("Do'konlar")
String tr(String uz) => L10n.tr(uz);

/// Daraja nomi (serverdan o'zbekcha keladi)
String trLevel(String level) => level == 'Yangi'
    ? (L10n.lang == AppLang.uz ? 'Yangi' : tr('Yangi_lvl'))
    : tr(level);
