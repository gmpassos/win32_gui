// Pure Dart logic (no Win32 calls): runs on any OS.
import 'package:logging/logging.dart' as logging;
import 'package:test/test.dart';
import 'package:win32_gui/win32_gui.dart';
import 'package:win32_gui/win32_gui_logging.dart';

/// A [Dialog] that is never created (no `HWND`): [doClose] is a no-op.
class _TestDialog<R> extends Dialog<R> {
  _TestDialog({
    super.title,
    super.width,
    super.height,
    super.items,
    super.fontName,
    super.fontSize,
    super.timeout,
  });

  int closeCount = 0;

  @override
  void doClose() {
    ++closeCount;
    super.doClose();
  }
}

void main() {
  group('DialogItem', () {
    test('==/hashCode', () {
      var a = DialogItem.text(
        x: 1,
        y: 2,
        width: 30,
        height: 10,
        id: 1,
        text: 'a',
      );
      var a2 = DialogItem.text(
        x: 1,
        y: 2,
        width: 30,
        height: 10,
        id: 1,
        text: 'a',
      );
      var b = DialogItem.text(
        x: 1,
        y: 2,
        width: 30,
        height: 10,
        id: 1,
        text: 'b',
      );

      expect(a, equals(a2));
      expect(a.hashCode, equals(a2.hashCode));
      expect(a, isNot(equals(b)));
      expect(a.toString(), contains('text: a'));
    });

    test('button defaults', () {
      var item = DialogItem.button(
        x: 0,
        y: 0,
        width: 50,
        height: 14,
        id: 1,
        text: 'OK',
      );

      // The predefined `button` class (an ordinal `0` is invalid):
      expect(item.windowSystemClass, equals(DLG_CLASS_BUTTON));
      expect(item.windowClass, isEmpty);

      for (var flag in [WS_CHILD, WS_VISIBLE, WS_TABSTOP]) {
        expect(item.style & flag, equals(flag));
      }
      expect(item.style & BS_DEFPUSHBUTTON, equals(BS_DEFPUSHBUTTON));

      var custom = DialogItem.button(
        style: WS_CHILD | WS_VISIBLE,
        x: 0,
        y: 0,
        width: 50,
        height: 14,
        id: 1,
        text: 'OK',
      );
      expect(custom.style & WS_TABSTOP, equals(0));
    });

    test('text defaults', () {
      var item = DialogItem.text(
        x: 0,
        y: 0,
        width: 50,
        height: 14,
        id: 1,
        text: 'Hello',
      );

      expect(item.windowClass, equals('static'));
      expect(item.style & WS_CHILD, equals(WS_CHILD));
      expect(item.style & WS_VISIBLE, equals(WS_VISIBLE));
    });

    test('computeTemplateSize', () {
      var text = DialogItem.text(
        x: 0,
        y: 0,
        width: 50,
        height: 14,
        id: 1,
        text: 'Hello',
      );
      // header(9) + 'static'(7) + 'Hello'(6) + creation data(1) + align(1):
      expect(text.computeTemplateSize(), equals(24));

      var button = DialogItem.button(
        x: 0,
        y: 0,
        width: 50,
        height: 14,
        id: 1,
        text: 'OK',
      );
      // header(9) + ordinal(2) + 'OK'(3) + creation data(1) + align(1):
      expect(button.computeTemplateSize(), equals(16));

      var withData = DialogItem(
        style: WS_CHILD,
        x: 0,
        y: 0,
        width: 1,
        height: 1,
        id: 1,
        windowClass: 'x',
        creationDataBytes: [1, 2, 3],
      );
      // header(9) + 'x'(2) + ''(1) + size(1) + 3 bytes(2) + align(1):
      expect(withData.computeTemplateSize(), equals(16));
    });
  });

  group('Dialog template', () {
    test('header and item layout', () {
      var dialog = _TestDialog<int>(
        items: [
          DialogItem.button(
            x: 4,
            y: 30,
            width: 50,
            height: 14,
            id: 7,
            text: 'OK',
          ),
        ],
      );

      final template = dialog.createDialogTemplate();
      try {
        final header = template.ref;

        expect(header.cdit, equals(1));
        // `CW_USEDEFAULT` can't be used in a 16-bit `DLGTEMPLATE`:
        expect(header.x, equals(0));
        expect(header.y, equals(0));
        expect(header.cx, equals(Dialog.defaultWidth));
        expect(header.cy, equals(Dialog.defaultHeight));

        // Header (9) + menu (1) + class (1) + empty title (1) = 12 WORDs,
        // then the `DLGITEMTEMPLATE` (9) and the item class array:
        final words = template.cast<Uint16>();
        expect(words[9], equals(0)); // No menu.
        expect(words[10], equals(0)); // Default dialog class.
        expect(words[11], equals(0)); // No title.
        expect(words[12 + 9], equals(0xFFFF));
        expect(words[12 + 9 + 1], equals(DLG_CLASS_BUTTON));
      } finally {
        free(template);
      }
    });

    test('defined dimensions', () {
      var dialog = _TestDialog<int>(width: 120, height: 60);

      final template = dialog.createDialogTemplate();
      try {
        expect(template.ref.cx, equals(120));
        expect(template.ref.cy, equals(60));
      } finally {
        free(template);
      }
    });

    test('many items with long texts (no overflow)', () {
      var items = List.generate(
        30,
        (i) => DialogItem.text(
          x: 4,
          y: 4 + i * 10,
          width: 300,
          height: 10,
          id: i + 1,
          text: 'Item #$i: ${'x' * 100}',
        ),
      );

      var dialog = _TestDialog<int>(
        title: 'A dialog with a long title: ${'t' * 50}',
        fontName: 'MS Shell Dlg',
        fontSize: 8,
        items: items,
      );

      // Previously a fixed size (~13 WORDs per item) that overflowed:
      var size = dialog.computeDialogTemplateSize();
      expect(size, greaterThan(30 * 100));

      // Throws `StateError` if the written size exceeds the allocated one:
      final template = dialog.createDialogTemplate();
      free(template);
    });
  });

  group('Dialog result', () {
    test('finish (first result wins)', () {
      var dialog = _TestDialog<int>();

      expect(dialog.isResultSet, isFalse);
      expect(dialog.created, isFalse);

      dialog.finish(1);
      expect(dialog.isResultSet, isTrue);
      expect(dialog.result, equals(1));
      expect(dialog.closeCount, equals(1));

      dialog.finish(2);
      expect(dialog.result, equals(1));
      expect(dialog.closeCount, equals(1));
    });

    test('waitResult', () async {
      var dialog = _TestDialog<int>();

      var wait1 = dialog.waitResult();
      var wait2 = dialog.waitResult(timeout: Duration(milliseconds: 50));

      // Each caller has its own timeout:
      expect(await wait2, isFalse);

      dialog.finish(3);

      expect(await wait1, isTrue);
      expect(await dialog.waitResult(), isTrue);
      expect(await dialog.waitAndGetResult(), equals(3));
    });

    test('destroyed without a result', () async {
      var dialog = _TestDialog<int>();

      var destroyed = <Dialog>[];
      var destroyedDone = false;
      dialog.onDestroyed.listen(
        destroyed.add,
        onDone: () => destroyedDone = true,
      );

      var wait = dialog.waitResult();

      dialog.notifyDestroyed();

      expect(await wait, isFalse);
      expect(await dialog.waitResult(), isFalse);
      expect(dialog.isDestroyed, isTrue);
      expect(dialog.isResultSet, isFalse);
      expect(Dialog.dialogs, isNot(contains(dialog)));

      await pumpEventQueue();
      expect(destroyed, equals([dialog]));
      expect(destroyedDone, isTrue);

      // A second notification is ignored:
      dialog.notifyDestroyed();
    });

    test('setResultDynamic', () {
      var dInt = _TestDialog<int>();
      // A `WM_COMMAND` [wParam, lParam] (`BN_CLICKED` for id 2):
      expect(dInt.setResultDynamic([2, 0]), isTrue);
      expect(dInt.result, equals(2));

      var dString = _TestDialog<String>();
      expect(dString.setResultDynamic('x'), isTrue);
      expect(dString.result, equals('x'));

      var dString2 = _TestDialog<String>();
      expect(dString2.setResultDynamic([1, 2]), isTrue);
      expect(dString2.result, equals('1,2'));

      var dRecord = _TestDialog<(int, int)>();
      expect(dRecord.setResultDynamic([3, 4]), isTrue);
      expect(dRecord.result, equals((3, 4)));

      var dBool = _TestDialog<bool>();
      expect(dBool.setResultDynamic('x'), isFalse);
      expect(dBool.isResultSet, isFalse);
      expect(dBool.closeCount, equals(0));
    });

    test('isClickCommand', () {
      // `BN_CLICKED` (0) for control id 5:
      expect(Dialog.isClickCommand(5), isTrue);
      // Accelerator (1):
      expect(Dialog.isClickCommand((1 << 16) | 1), isTrue);
      // `EN_SETFOCUS` (0x0100) and `EN_CHANGE` (0x0300):
      expect(Dialog.isClickCommand((0x0100 << 16) | 5), isFalse);
      expect(Dialog.isClickCommand((0x0300 << 16) | 5), isFalse);
    });

    test('timeout', () async {
      var dialog = _TestDialog<int>(timeout: Duration(milliseconds: 50));

      // Started by `create()`, not by the constructor:
      expect(dialog.timeoutTimer, isNull);

      var onTimeout = dialog.onTimeout.first;
      dialog.setupTimeout();
      expect(dialog.timeoutTimer, isNotNull);

      var timedOut = await onTimeout.timeout(Duration(seconds: 5));
      expect(timedOut, same(dialog));
      expect(dialog.timeoutTriggered, isTrue);
      expect(dialog.isResultSet, isTrue);
      expect(dialog.result, isNull);
      expect(dialog.timeoutTimer, isNull);
    });

    test('timeout cancelled by a result', () async {
      var dialog = _TestDialog<int>(timeout: Duration(milliseconds: 50));

      dialog.setupTimeout();
      dialog.finish(1);
      expect(dialog.timeoutTimer, isNull);

      await Future.delayed(Duration(milliseconds: 100));
      expect(dialog.timeoutTriggered, isFalse);
      expect(dialog.result, equals(1));
    });
  });

  group('Win32Constants', () {
    test('wmByID only has `WM_*` messages', () {
      expect(Win32Constants.wmByID.values, everyElement(startsWith('WM_')));
    });

    test('values match package:win32', () {
      expect(Win32Constants.wmByName['WM_CREATE'], equals(WM_CREATE));
      expect(Win32Constants.wmByName['WM_COMMAND'], equals(WM_COMMAND));
      expect(
        Win32Constants.wmByName['WM_CTLCOLORSTATIC'],
        equals(WM_CTLCOLORSTATIC),
      );
      expect(
        Win32Constants.wmByName['WM_CTLCOLOREDIT'],
        equals(WM_CTLCOLOREDIT),
      );
      expect(Win32Constants.wmByID[WM_CTLCOLORBTN], equals('WM_CTLCOLORBTN'));
      expect(Win32Constants.wmByID[4], isNull);
    });

    test('extra constants', () {
      expect(Win32Constants.wmByName['CFM_COLOR'], equals(CFM_COLOR));
      expect(Win32Constants.wmByName['SCF_ALL'], equals(SCF_ALL));
      expect(
        Win32Constants.buildConstants(),
        contains('const WM_CREATE = $WM_CREATE;'),
      );
    });
  });

  group('WindowClass/Window (predefined class)', () {
    test('WindowClass.predefined', () {
      var wc = WindowClass.predefined(className: 'static');
      expect(WindowClass.predefined(className: 'static'), same(wc));
      expect(wc.custom, isFalse);

      // No Win32 call for predefined classes:
      expect(wc.register(), isTrue);
      expect(wc.isRegisteredOK, isTrue);
    });

    test('Window registration and lookup', () {
      var wc = WindowClass.predefined(className: 'static');

      var w = Window(
        windowClass: wc,
        windowName: 'logic-test',
        defaultRepaint: true,
      );

      expect(w.created, isFalse);
      expect(w.hwndIfCreated, isNull);
      expect(() => w.hwnd, throwsStateError);

      expect(wc.windows, contains(w));
      expect(WindowClass.allWindows, contains(w));

      expect(wc.getWindowWithCreateId(w.createId), same(w));
      expect(
        wc.getWindowWithCreateId(w.createId, windowName: 'logic-test'),
        same(w),
      );
      expect(wc.getWindowWithCreateId(w.createId, windowName: 'other'), isNull);
      expect(wc.getWindowWithCreateId(-1), isNull);

      expect(
        wc.getWindowWithHWnd(HWND(Pointer.fromAddress(0x1234)), global: true),
        isNull,
      );

      expect(w.windowNameNative!.toDartString(), equals('logic-test'));
      expect(w.dimensionWidth, equals(0));
      expect(w.dimensionHeight, equals(0));

      w.notifyDestroyed();
      expect(wc.windows, isNot(contains(w)));
    });

    test('Window without name', () {
      var w = Window(
        windowClass: WindowClass.predefined(className: 'static'),
        defaultRepaint: true,
      );

      expect(w.windowNameNative, isNull);
      w.notifyDestroyed();
    });

    test('children are notified when the parent is destroyed', () async {
      var parent = Window(
        windowClass: WindowClass.predefined(className: 'static'),
        windowName: 'parent',
        defaultRepaint: true,
      );

      var child = ChildWindow(
        parent: parent,
        windowClass: WindowClass.predefined(className: 'static'),
        defaultRepaint: true,
      );

      var button = Button(label: 'OK', parent: parent);

      expect(parent.children, equals([child, button]));
      expect(button.id, greaterThan(child.id));
      expect(button.windowStyles & WS_CHILD, equals(WS_CHILD));
      expect(Button.buttonWindowClass.windows, contains(button));

      var parentEvents = 0;
      var parentDone = false;
      parent.onDestroyed.listen(
        (_) => ++parentEvents,
        onDone: () => parentDone = true,
      );

      parent.notifyDestroyed();

      expect(parent.isDestroyed, isTrue);
      expect(child.isDestroyed, isTrue);
      expect(button.isDestroyed, isTrue);
      expect(Button.buttonWindowClass.windows, isNot(contains(button)));

      await pumpEventQueue();
      expect(parentEvents, equals(1));
      expect(parentDone, isTrue);
    });
  });

  group('WindowClassColors', () {
    test('toString', () {
      var colors = WindowClassColors(textColor: 1, bgColor: 2);
      expect(colors.toString(), contains('textColor: 1'));
      expect(colors.toString(), contains('bgColor: 2'));

      // Nothing to release (no brush created):
      colors.dispose();
    });

    test('createCtlColorBrush without colors', () {
      expect(WindowClass.createCtlColorBrush(null, 0), equals(0));
    });
  });

  group('TextFormatted', () {
    test('==/hashCode', () {
      var a = TextFormatted('a', bold: true, color: 1);
      var a2 = TextFormatted('a', bold: true, color: 1);
      var b = TextFormatted('a', color: 1);

      expect(a, equals(a2));
      expect(a.hashCode, equals(a2.hashCode));
      expect(a, isNot(equals(b)));
    });
  });

  group('Logging', () {
    test('LoggerHandler.parent', () {
      var handler = logging.Logger('win32_gui_test.parent.child').handler;
      expect(handler.parent?.logger.fullName, equals('win32_gui_test.parent'));
      expect(LoggerHandler.root.parent, isNull);
    });

    test('truncateString', () {
      expect(LoggerHandler.truncateString('abc', 10), equals('abc'));

      var s = LoggerHandler.truncateString('abcdefghijklmnopqrstuvwxyz', 10);
      expect(s.length, equals(10));
      expect(s, equals('abcdef..yz'));
    });

    test('buildMessageText truncates long logger names', () {
      var longName = 'L' * 60;
      var record = logging.LogRecord(logging.Level.INFO, 'hello', longName);

      var text = LoggerHandler.root.buildMessageText(record);

      expect(text, contains('> hello'));
      expect(text, isNot(contains(longName)));
    });

    test('logAllTo', () async {
      var messages = <String>[];
      logAllTo(messageLogger: (level, m) => messages.add(m));

      try {
        logging.Logger('win32_gui_test.all').info('logAllTo-message');
        await pumpEventQueue();

        expect(messages, contains(contains('logAllTo-message')));
      } finally {
        logAllTo(messageLogger: null);
      }
    });

    test('logErrorTo for a specific logger', () async {
      var logger = logging.Logger('win32_gui_test.errors');

      var errors = <String>[];
      logger.handler.logErrorTo(messageLogger: (level, m) => errors.add(m));

      logger.severe('severe-message');
      logger.info('info-message');
      await pumpEventQueue();

      expect(errors, [contains('severe-message')]);
    });
  });
}
