import 'package:logging/logging.dart';

final _logger = Logger('mariannmt_wrapper');

void debug(String message) {
  _logger.fine(message);
}

void info(String message) {
  _logger.info(message);
}

void warning(String message) {
  _logger.warning(message);
}

void error(String message) {
  _logger.severe(message);
}
