/// Ramadan's dates, Umm al-Qura.
///
/// Read off Apple's Calendar(identifier: .islamicUmmAlQura) on 2026-09-25
/// for 1447 to 1475 AH (2026 to 2053), the calendar Saudi Arabia publishes
/// ahead of time. The Gulf starts Ramadan by moon sighting, which lands on
/// the same day or one day either side, so anything that opens "in
/// Ramadan" should give a day of room at each end (see
/// app_icon_catalog.dart's [RamadanIconWindow]).
///
/// A table rather than a conversion: there is no Hijri calendar in Dart's
/// libraries, Umm al-Qura is itself a published table, and these 29 rows
/// are the whole of it the app will need for a long time. A test fails
/// once fewer than ten years are left in it.
library;

/// 1 Ramadan and 1 Shawwal (Eid al-Fitr) of each year, as yyyymmdd.
const List<(int, int, int)> _kRamadan = [
  (1447, 20260218, 20260320),
  (1448, 20270208, 20270309),
  (1449, 20280128, 20280226),
  (1450, 20290116, 20290214),
  (1451, 20300105, 20300204),
  (1452, 20301226, 20310124),
  (1453, 20311216, 20320114),
  (1454, 20321204, 20330103),
  (1455, 20331123, 20331223),
  (1456, 20341112, 20341212),
  (1457, 20351101, 20351201),
  (1458, 20361021, 20361119),
  (1459, 20371010, 20371109),
  (1460, 20380930, 20381029),
  (1461, 20390919, 20391019),
  (1462, 20400908, 20401007),
  (1463, 20410828, 20410927),
  (1464, 20420817, 20420916),
  (1465, 20430806, 20430905),
  (1466, 20440726, 20440824),
  (1467, 20450716, 20450814),
  (1468, 20460705, 20460804),
  (1469, 20470625, 20470724),
  (1470, 20480613, 20480713),
  (1471, 20490602, 20490702),
  (1472, 20500522, 20500621),
  (1473, 20510512, 20510610),
  (1474, 20520430, 20520530),
  (1475, 20530420, 20530519),
];

DateTime _day(int yyyymmdd) =>
    DateTime(yyyymmdd ~/ 10000, yyyymmdd ~/ 100 % 100, yyyymmdd % 100);

/// One Ramadan: its first day and Eid al-Fitr's, both local midnights.
class RamadanDates {
  const RamadanDates(this.hijriYear, this.start, this.eid);

  final int hijriYear;
  final DateTime start;
  final DateTime eid;
}

/// Every Ramadan in the table, oldest first.
List<RamadanDates> get ramadanTable => [
      for (final (year, start, eid) in _kRamadan)
        RamadanDates(year, _day(start), _day(eid)),
    ];

/// The first Ramadan whose Eid is on or after [day]'s date: the one [day]
/// is in, or the next. Null once the table has run out.
RamadanDates? ramadanOnOrAfter(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  for (final r in ramadanTable) {
    if (!r.eid.isBefore(date)) return r;
  }
  return null;
}
