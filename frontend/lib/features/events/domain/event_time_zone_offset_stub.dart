/// Off the web (tests in the Dart VM): zones without summer time only.
/// The app itself is web-only and uses the browser's data.
const _fixed = <String, int>{
  'UTC': 0,
  'Asia/Kolkata': 330,
  'Asia/Dubai': 240,
  'Asia/Singapore': 480,
  'Asia/Tokyo': 540,
  'Asia/Shanghai': 480,
  'Asia/Hong_Kong': 480,
  'Asia/Bangkok': 420,
  'Asia/Jakarta': 420,
  'Europe/Moscow': 180,
};

int? utcOffsetMinutes(DateTime instant, String zone) => _fixed[zone];
