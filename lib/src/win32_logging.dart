import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart' as logging;

final Expando<LoggerHandler> _loggerHandlers = Expando<LoggerHandler>();

bool _bootCalled = false;

void _boot() {
  if (_bootCalled) return;
  _bootCalled = true;

  _setupRootLogger();
}

void _setupRootLogger() {
  var loggerHandler = _resolveLoggerHandler();
  var rootLogger = LoggerHandler.rootLogger;
  rootLogger.onRecord.listen(loggerHandler._logRootMsg);
}

LoggerHandler _resolveLoggerHandler([LoggerHandler? loggerHandler]) {
  _boot();
  return loggerHandler ?? LoggerHandler.root;
}

void logAllTo(
    {MessageLogger? messageLogger,
    Object? logDestiny,
    bool includeDBLogs = false}) {
  var loggerHandler = _resolveLoggerHandler();
  loggerHandler.logAllTo(
      messageLogger: messageLogger,
      logDestiny: logDestiny,
      includeDBLogs: includeDBLogs);
}

void logToConsole({bool enabled = true}) {
  var loggerHandler = _resolveLoggerHandler();
  loggerHandler.logToConsole(enabled: enabled);
}

void logErrorTo(
    {MessageLogger? messageLogger,
    Object? logDestiny,
    LoggerHandler? loggerHandler}) {
  loggerHandler = _resolveLoggerHandler(loggerHandler);
  loggerHandler.logErrorTo(
      messageLogger: messageLogger, logDestiny: logDestiny);
}

void logDbTo(
    {MessageLogger? messageLogger,
    Object? logDestiny,
    LoggerHandler? loggerHandler}) {
  loggerHandler = _resolveLoggerHandler(loggerHandler);
  loggerHandler.logDbTo(messageLogger: messageLogger, logDestiny: logDestiny);
}

extension LoggerExntesion on logging.Logger {
  LoggerHandler get handler {
    var handler = _loggerHandlers[this];
    if (handler == null) {
      handler = LoggerHandler._(this);
      _loggerHandlers[this] = handler;
    }
    return handler;
  }
}

typedef MessageLogger = void Function(logging.Level level, String message);
typedef MessagesBlockLogger = Future<void> Function(
    logging.Level level, List<String> messages);

class LoggerHandler {
  static String truncateString(String s, int limit) {
    if (s.length > limit) {
      s = '${s.substring(0, limit - 4)}..${s.substring(s.length - 2)}';
    }
    return s;
  }

  static logging.Logger get rootLogger => logging.Logger.root;

  static LoggerHandler get root => rootLogger.handler;

  static int _idCount = 0;

  final int id = ++_idCount;

  final logging.Logger logger;

  LoggerHandler._(this.logger) {
    _boot();
  }

  String get isolateDebugName {
    var s = Isolate.current.debugName as dynamic;
    return s != null ? '$s' : '?';
  }

  LoggerHandler? get parent {
    var l = logger.parent;
    if (l == null) return null;

    var handler = _loggerHandlers[this];
    return handler;
  }

  String loggerName(logging.LogRecord msg) {
    var name = msg.loggerName;
    if (name == 'hotreloader') {
      name = 'APIHotReload';
    }
    return name;
  }

  static final Map<String, QueueList<int>> _maxKeys =
      <String, QueueList<int>>{};

  static int _maxKey(String key, String s, int limit) {
    var maxList = _maxKeys[key];
    var sLength = s.length;

    if (maxList == null) {
      var max = sLength;
      _maxKeys[key] = QueueList.from([sLength]);
      return max;
    } else {
      maxList.addLast(sLength);
      while (maxList.length > 20) {
        maxList.removeFirst();
      }
      var max = _listMax(maxList);
      return max;
    }
  }

  static int _listMax(List<int> l) {
    var max = l.first;
    for (var n in l.skip(1)) {
      if (n > max) {
        max = n;
      }
    }
    return max;
  }

  void _logRootMsg(logging.LogRecord msg) {
    var level = msg.level;
    var logMsg = _buildMsg(msg);

    if (level == logging.Level.SEVERE) {
      logErrorMessage(level, logMsg);
    }

    if (_logToConsole) {
      printMessage(level, logMsg);
    }
  }

  String _buildMsg(logging.LogRecord msg) {
    var time = '${msg.time}'.padRight(26, '0');
    var levelName = '[${msg.level.name}]'.padRight(9);

    var debugName = isolateDebugName;
    if (debugName.isNotEmpty) {
      var max = _maxKey('debugName', debugName, 10);
      debugName = truncateString(debugName, max);
      debugName = '($debugName)'.padRight(max + 2);
    }

    var loggerName = this.loggerName(msg);
    if (loggerName.isNotEmpty) {
      var max = _maxKey('loggerName', loggerName, 20);
      loggerName = truncateString(loggerName, max);
      loggerName = loggerName.padRight(max);
    }

    var message = msg.message;

    var logMsg =
        StringBuffer('$time $levelName $debugName $loggerName> $message\n');

    if (msg.error != null) {
      logMsg.write('[ERROR] ');
      logMsg.write(msg.error.toString());
      logMsg.write('\n');
    }

    if (msg.stackTrace != null) {
      logMsg.write(msg.stackTrace.toString());
      logMsg.write('\n');
    }

    return logMsg.toString();
  }

  void printMessage(logging.Level level, String message) {
    var out = (level < logging.Level.SEVERE ? stdout : stderr);
    out.write(message);
  }

  void logAll() {
    logging.hierarchicalLoggingEnabled = true;
    logger.level = logging.Level.ALL;
  }

  static MessageLogger? _allMessageLogger;

  static MessageLogger? getLogAllTo() => _allMessageLogger;

  void logAllTo(
      {MessageLogger? messageLogger,
      Object? logDestiny,
      bool includeDBLogs = false}) {
    messageLogger ??= resolveLogDestiny(logDestiny);

    _allMessageLogger = messageLogger;
  }

  void logToConsole({bool enabled = true}) => _logToConsoleImpl(enabled);

  static bool _logToConsole = false;

  static bool getLogToConsole() => _logToConsole;

  static void _logToConsoleImpl(bool enabled) => _logToConsole = enabled;

  MessageLogger? _errorMessageLogger;

  MessageLogger? getLogErrorTo() => _errorMessageLogger;

  void logErrorTo({MessageLogger? messageLogger, Object? logDestiny}) {
    messageLogger ??= resolveLogDestiny(logDestiny);

    _errorMessageLogger = messageLogger;
  }

  MessageLogger? _dbMessageLogger;

  MessageLogger? getLogDbTo() => _dbMessageLogger;

  void logDbTo({MessageLogger? messageLogger, Object? logDestiny}) {
    messageLogger ??= resolveLogDestiny(logDestiny);

    _dbMessageLogger = messageLogger;
  }

  void logAllMessage(logging.Level level, String message) {
    var messageLogger = _allMessageLogger;

    if (messageLogger != null) {
      messageLogger(level, message);
    }
  }

  void logErrorMessage(logging.Level level, String message) {
    var messageLogger = _errorMessageLogger;

    if (messageLogger == null) {
      var parent = this.parent;
      messageLogger = parent?._errorMessageLogger;
      messageLogger ??= LoggerHandler.root._errorMessageLogger;
    }

    if (messageLogger != null) {
      messageLogger(level, message);
    }
  }

  void logDBMessage(logging.Level level, String message) {
    var messageLogger = _dbMessageLogger;

    if (messageLogger == null) {
      var parent = this.parent;
      messageLogger = parent?._dbMessageLogger;
      messageLogger ??= LoggerHandler.root._dbMessageLogger;
    }

    if (messageLogger != null) {
      messageLogger(level, message);
    }
  }

  MessageLogger? resolveLogDestiny(final Object? logDestiny) {
    if (logDestiny == null) return null;

    if (logDestiny is Map) {
      var destiny =
          logDestiny['to'] ?? logDestiny['path'] ?? logDestiny['file'];
      if (destiny != null) {
        return resolveLogDestiny(destiny);
      }
    }

    if (logDestiny is MessageLogger) return logDestiny;

    if (logDestiny == 'console' || logDestiny == 'stdout') {
      return printMessage;
    }

    if (logDestiny is Function(Object, Object)) {
      return (l, m) => logDestiny(l, m);
    } else if (logDestiny is Function(dynamic, dynamic)) {
      return (l, m) => logDestiny(l, m);
    }

    if (logDestiny is Function(Object)) {
      return (l, m) => logDestiny(m);
    } else if (logDestiny is Function(dynamic)) {
      return (l, m) => logDestiny(m);
    }

    return null;
  }
}
