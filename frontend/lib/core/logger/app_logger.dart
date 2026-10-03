import 'package:logger/logger.dart';

abstract class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      colors: true,
      printEmojis: true,
    ),
  );

  static void debug(String message) => _logger.d(message);

  static void info(String message) => _logger.i(message);

  static void warning(String message) => _logger.w(message);

  static void error(String message, [dynamic err, StackTrace? stackTrace]) =>
      _logger.e(message, error: err, stackTrace: stackTrace);
}
