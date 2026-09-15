/// Viloyatlar: server (server/src/util.js REGIONS) bilan bir xil nomlar.
/// Ro'yxatdan o'tishda serverga aynan shu nomlar yuboriladi.
const kRegions = <String>[
  'Toshkent shahri', 'Toshkent viloyati', 'Andijon', "Farg'ona", 'Namangan', 'Samarqand', 'Buxoro', 'Navoiy',
  'Qashqadaryo', 'Surxondaryo', 'Jizzax', 'Sirdaryo', 'Xorazm', "Qoraqalpog'iston",
];

/// Viloyat markazlari: xaritada joy belgilashda boshlang'ich nuqta
const kRegionCoords = <String, List<double>>{
  'Toshkent shahri': [41.311, 69.240], 'Toshkent viloyati': [41.040, 69.357], 'Andijon': [40.783, 72.344], "Farg'ona": [40.389, 71.787],
  'Namangan': [40.998, 71.673], 'Samarqand': [39.655, 66.960], 'Buxoro': [39.768, 64.421], 'Navoiy': [40.103, 65.374],
  'Qashqadaryo': [38.861, 65.790], 'Surxondaryo': [37.224, 67.278], 'Jizzax': [40.116, 67.842], 'Sirdaryo': [40.490, 68.784],
  'Xorazm': [41.550, 60.631], "Qoraqalpog'iston": [42.460, 59.603],
};

/// Kuryer transporti (kod, nom)
const kVehicles = <(String, String)>[('foot', 'Piyoda'), ('bike', 'Velosiped'), ('moto', 'Mototsikl'), ('car', 'Mashina')];

/// Yuk tashuvchi mashinalari (kod, nom)
const kVehicleTypes = <(String, String)>[('labo', 'Labo'), ('damas', 'Damas'), ('gazel', 'Gazel'), ('isuzu', 'Isuzu'), ('fura', 'Fura')];
