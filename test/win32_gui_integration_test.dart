@TestOn('windows')
library;

import 'package:test/test.dart';
import 'package:win32_gui/win32_gui.dart';
import 'package:win32_gui/win32_gui_logging.dart';

// ignore: constant_identifier_names
const BM_CLICK = 0x00F5;

/// Processes Window messages for [duration].
Future<void> pump([Duration duration = const Duration(milliseconds: 300)]) =>
    Window.runMessageLoopAsync(timeout: duration);

/// Processes Window messages until [condition] is `true` (or [timeout]).
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) =>
    Window.runMessageLoopAsync(timeout: timeout, condition: () => !condition());

class _TestWindow extends Window {
  static final testWindowClass = WindowClass.custom(
    className: 'win32GuiIntegrationTestWindow',
    windowProc: Pointer.fromFunction<WNDPROC>(_windowProc, 0),
    bgColor: RGB(255, 255, 255),
  );

  static int _windowProc(Pointer hwnd, int uMsg, int wParam, int lParam) =>
      WindowClass.windowProcDefault(
        hwnd,
        uMsg,
        wParam,
        lParam,
        testWindowClass,
      );

  final bool? closeBehavior;
  final bool throwOnBuild;

  _TestWindow({
    super.windowName,
    this.closeBehavior = true,
    this.throwOnBuild = false,
  }) : super(
         windowClass: testWindowClass,
         windowStyles: WS_OVERLAPPEDWINDOW,
         width: 320,
         height: 240,
         defaultRepaint: false,
       );

  int buildCount = 0;
  int repaintCount = 0;

  @override
  void build(HWND hwnd, HDC hdc) {
    super.build(hwnd, hdc);
    ++buildCount;
    if (throwOnBuild) {
      throw StateError('Test error on build');
    }
  }

  @override
  void repaint(HWND hwnd, HDC hdc) {
    ++repaintCount;
  }

  @override
  bool? processClose() => closeBehavior;
}

void main() {
  logToConsole();

  group('Window', () {
    test('without a name', () async {
      // `CREATESTRUCT.lpszName` is `NULL` (it used to crash the process):
      var w = _TestWindow();
      expect(w.windowNameNative, isNull);

      await w.create();
      expect(w.created, isTrue);
      expect(w.buildCount, equals(1));

      w.destroy();
      expect(w.isDestroyed, isTrue);
    });

    test('repaint', () async {
      var w = _TestWindow(windowName: 'repaint');
      await w.create();
      w.show();

      await pumpUntil(() => w.repaintCount > 0);
      expect(w.repaintCount, greaterThan(0));

      // Outside `WM_PAINT` (uses `GetDC`, not `BeginPaint`):
      var count = w.repaintCount;
      expect(w.callRepaint(), isTrue);
      expect(w.repaintCount, equals(count + 1));

      w.destroy();
    });

    test('an error in build() fails create() (no crash)', () async {
      var w = _TestWindow(windowName: 'build-error', throwOnBuild: true);

      // `windowProcDefault` catches the error and returns `-1` to `WM_CREATE`:
      await expectLater(w.create(), throwsStateError);
      expect(w.buildCount, equals(1));
    });

    test('minimize/maximize/restore return the resulting state', () async {
      var w = _TestWindow(windowName: 'states');
      await w.create();
      w.show();
      await pump();

      expect(w.minimize(), isTrue);
      expect(w.isMinimized, isTrue);

      expect(w.restore(), isTrue);
      expect(w.isMinimized, isFalse);

      expect(w.maximize(), isTrue);
      expect(w.isMaximized, isTrue);

      expect(w.restore(), isTrue);
      expect(w.isMaximized, isFalse);

      w.destroy();
    });

    test('close() with the default behavior destroys the window', () async {
      var w = _TestWindow(windowName: 'close', closeBehavior: null);

      var closeEvents = 0;
      var destroyEvents = 0;
      var destroyDone = false;
      w.onClose.listen((_) => ++closeEvents);
      w.onDestroyed.listen(
        (_) => ++destroyEvents,
        onDone: () => destroyDone = true,
      );

      await w.create();
      w.show();
      await pump();

      // Win32 `CloseWindow` would only minimize it:
      expect(w.close(), isTrue);
      expect(w.isDestroyed, isTrue);

      await pump();
      expect(closeEvents, equals(1));
      expect(destroyEvents, equals(1));
      expect(destroyDone, isTrue);
    });

    test('close() with processClose `true` minimizes', () async {
      var w = _TestWindow(windowName: 'close-minimize', closeBehavior: true);
      await w.create();
      w.show();
      await pump();

      expect(w.close(), isFalse);
      expect(w.isDestroyed, isFalse);
      expect(w.isMinimized, isTrue);

      w.destroy();
    });

    test('children are destroyed with the parent', () async {
      var w = _TestWindow(windowName: 'parent');
      var button = Button(
        label: 'OK',
        parent: w,
        x: 4,
        y: 4,
        width: 80,
        height: 24,
      );

      await w.create();
      expect(button.created, isTrue);
      expect(Button.buttonWindowClass.windows, contains(button));

      w.destroy();

      expect(w.isDestroyed, isTrue);
      expect(button.isDestroyed, isTrue);
      expect(Button.buttonWindowClass.windows, isNot(contains(button)));
    });

    test('Button click calls onCommand', () async {
      var clicks = 0;

      var w = _TestWindow(windowName: 'button-click');
      var button = Button(
        label: 'OK',
        parent: w,
        x: 4,
        y: 4,
        width: 80,
        height: 24,
        onCommand: (wParam, lParam) => ++clicks,
      );

      await w.create();
      w.show();
      await pump();

      button.sendMessage(BM_CLICK, 0, 0);
      await pumpUntil(() => clicks > 0);
      expect(clicks, equals(1));

      w.destroy();
    });

    test('a duplicated custom class name is not registered', () async {
      var w = _TestWindow(windowName: 'register');
      await w.create();
      expect(_TestWindow.testWindowClass.isRegisteredOK, isTrue);

      var duplicated = WindowClass.custom(
        className: _TestWindow.testWindowClass.className,
        windowProc: _TestWindow.testWindowClass.windowProc,
      );
      expect(duplicated.register(), isFalse);
      expect(duplicated.isRegisteredOK, isFalse);

      w.destroy();
    });

    test('getSystemDefaultFonts', () {
      var fonts = Window.getSystemDefaultFonts();
      expect(
        fonts.keys,
        unorderedEquals(['caption', 'menu', 'message', 'status']),
      );
      expect(fonts.values, everyElement(isNotEmpty));
    });
  });

  group('WindowClassColors', () {
    test('brush is cached (no GDI leak per WM_CTLCOLOR*)', () {
      var colors = WindowClassColors(
        textColor: RGB(0, 0, 0),
        bgColor: RGB(200, 200, 200),
      );

      final hdc = GetDC(null);
      try {
        var brush1 = colors.brush(hdc);
        var brush2 = colors.brush(hdc);

        expect(brush1.isNull, isFalse);
        expect(brush2.address, equals(brush1.address));

        var ctlBrush = WindowClass.createCtlColorBrush(colors, hdc.address);
        expect(ctlBrush, equals(brush1.address));

        // `createSolidBrush` returns a new brush owned by the caller:
        var owned = colors.createSolidBrush(hdc);
        expect(owned.address, isNot(equals(brush1.address)));
        DeleteObject(HGDIOBJ(owned));
      } finally {
        ReleaseDC(null, hdc);
        colors.dispose();
      }
    });
  });

  group('WindowMessageLoop', () {
    test('runLoopAsync stops on WM_QUIT', () async {
      var sw = Stopwatch()..start();

      Window.quit(0);
      await Window.runMessageLoopAsync(timeout: Duration(seconds: 10));

      expect(sw.elapsed, lessThan(Duration(seconds: 5)));
    });

    test('consumeQueue keeps WM_QUIT', () async {
      var sw = Stopwatch()..start();

      Window.quit(0);
      WindowMessageLoop.consumeQueue();

      // The `WM_QUIT` was re-posted:
      await Window.runMessageLoopAsync(timeout: Duration(seconds: 10));

      expect(sw.elapsed, lessThan(Duration(seconds: 5)));
    });
  });

  group('Dialog', () {
    test('button click sets the result and destroys it', () async {
      var dialog = Dialog<int>(
        title: 'Click',
        width: 120,
        height: 60,
        items: [
          DialogItem.button(
            x: 4,
            y: 30,
            width: 50,
            height: 14,
            id: 7,
            text: 'Seven',
          ),
        ],
      );

      await dialog.create();
      expect(dialog.created, isTrue);

      // The button control exists (the `button` class ordinal is valid):
      final hButton = GetDlgItem(dialog.hwnd, 7).value;
      expect(hButton.isNull, isFalse);

      SendMessage(hButton, BM_CLICK, WPARAM(0), LPARAM(0));
      await pumpUntil(() => dialog.isDestroyed);

      expect(dialog.isResultSet, isTrue);
      expect(dialog.result, equals(7));
      expect(dialog.isDestroyed, isTrue);
      expect(await dialog.waitResult(), isTrue);
    });

    test('closed by the user: waitResult completes with false', () async {
      var dialog = Dialog<int>(title: 'Close', width: 120, height: 60);

      await dialog.create();

      var wait = dialog.waitResult();

      // Like the title bar X (or Alt+F4):
      dialog.sendMessage(WM_CLOSE, 0, 0);

      expect(dialog.isDestroyed, isTrue);
      expect(await wait.timeout(Duration(seconds: 5)), isFalse);
      expect(dialog.isResultSet, isFalse);
      expect(Dialog.dialogs, isNot(contains(dialog)));
    });

    test('timeout (started on create)', () async {
      var dialog = Dialog<int>(
        title: 'Timeout',
        width: 120,
        height: 60,
        timeout: Duration(milliseconds: 300),
      );

      expect(dialog.timeoutTimer, isNull);

      var onTimeout = dialog.onTimeout.first;

      await dialog.create();
      expect(dialog.timeoutTimer, isNotNull);

      await pumpUntil(() => dialog.isDestroyed);

      expect(await onTimeout.timeout(Duration(seconds: 5)), same(dialog));
      expect(dialog.timeoutTriggered, isTrue);
      expect(dialog.isDestroyed, isTrue);
      expect(dialog.result, isNull);
    });

    test('focus notifications don\'t set the result', () async {
      var dialog = Dialog<int>(
        title: 'Edit',
        width: 160,
        height: 60,
        items: [
          DialogItem(
            style: WS_CHILD | WS_VISIBLE | WS_BORDER | WS_TABSTOP,
            x: 4,
            y: 4,
            width: 100,
            height: 14,
            id: 5,
            windowClass: 'edit',
          ),
        ],
      );

      await dialog.create();

      final hEdit = GetDlgItem(dialog.hwnd, 5).value;
      expect(hEdit.isNull, isFalse);

      // `EN_SETFOCUS` used to set the result and close the dialog:
      SetFocus(hEdit);
      await pump();

      expect(dialog.isResultSet, isFalse);
      expect(dialog.isDestroyed, isFalse);

      dialog.destroy();
      expect(dialog.isDestroyed, isTrue);
    });

    test('many items with long texts', () async {
      var dialog = Dialog<int>(
        title: 'Items',
        width: 300,
        height: 400,
        items: List.generate(
          20,
          (i) => DialogItem.text(
            x: 4,
            y: 4 + i * 12,
            width: 290,
            height: 10,
            id: 100 + i,
            text: 'Item #$i ${'x' * 60}',
          ),
        ),
      );

      await dialog.create();
      expect(dialog.created, isTrue);

      final hLast = GetDlgItem(dialog.hwnd, 119).value;
      expect(hLast.isNull, isFalse);

      dialog.destroy();
    });
  });

  group('RichEdit', () {
    test('appendText and getCharFormat', () async {
      var w = _TestWindow(windowName: 'rich-edit');
      var richEdit = RichEdit(parent: w, x: 4, y: 4, width: 300, height: 200);

      await w.create();
      expect(richEdit.created, isTrue);

      richEdit.appendText('Hello', bold: true, color: RGB(255, 0, 0));
      richEdit.appendText(' World');

      expect(richEdit.getWindowText(), contains('Hello World'));

      final cf = richEdit.getCharFormat();
      try {
        expect(cf.ref.cbSize, equals(sizeOf<CHARFORMAT>()));
      } finally {
        free(cf);
      }

      w.destroy();
      expect(richEdit.isDestroyed, isTrue);
    });
  });
}
