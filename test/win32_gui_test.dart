@TestOn('windows')
import 'dart:io';

import 'package:test/test.dart';
import 'package:win32_gui/win32_gui.dart';
import 'package:win32_gui/win32_gui_logging.dart';

void main() {
  logToConsole();

  test('Basic Window', () async {
    var editorClass = WindowClassColors(
      textColor: RGB(0, 0, 0),
      bgColor: RGB(128, 128, 128),
    );

    WindowClass.editColors = editorClass;
    WindowClass.staticColors = editorClass;

    var mainWindow = _MainWindow(
      width: 640,
      height: 480,
    );

    print('-- mainWindow.create...');
    await mainWindow.create();

    var receivedOnClose = false;
    mainWindow.onClose.listen((_) => receivedOnClose = true);

    var receivedOnDestroyed = false;
    mainWindow.onDestroyed.listen((_) => receivedOnDestroyed = true);

    print('-- mainWindow.show...');
    mainWindow.show();

    print('-- Window.runMessageLoopAsync...');
    var messages =
        await Window.runMessageLoopAsync(timeout: Duration(seconds: 5));

    print('-- Window.runMessageLoopAsync finished> messages: $messages');

    expect(mainWindow.isDestroyed, isFalse);
    expect(mainWindow.textOutput.defaultFont, isNotEmpty);

    var systemDefaultFonts = Window.getSystemDefaultFonts();
    expect(systemDefaultFonts.keys,
        unorderedEquals(['caption', 'menu', 'message', 'status']));
    expect(systemDefaultFonts.values, everyElement(isNotEmpty));

    {
      print('-- Window.runMessageLoopAsync [close()]...');
      expect(receivedOnClose, isFalse);

      var msgLoop = Window.runMessageLoopAsync(
          timeout: Duration(seconds: 3), condition: () => !receivedOnClose);

      expect(receivedOnClose, isFalse);
      mainWindow.close();

      print('-- Waiting: Window.runMessageLoopAsync [close()]...');
      await msgLoop;

      print('-- Checking if received `OnClose`');
      expect(receivedOnClose, isTrue);

      expect(mainWindow.isDestroyed, isFalse);
      expect(mainWindow.isMinimized, isTrue);

      // Process messages for 2s to show close:
      await Window.runMessageLoopAsync(timeout: Duration(seconds: 2));
    }

    {
      print('-- Window.runMessageLoopAsync [restore()]...');
      expect(mainWindow.isMinimized, isTrue);

      var msgLoop = Window.runMessageLoopAsync(
          timeout: Duration(seconds: 3),
          condition: () => mainWindow.isMinimized);

      expect(mainWindow.isMinimized, isTrue);
      mainWindow.restore();

      print('-- Waiting: Window.runMessageLoopAsync [restore()]...');
      await msgLoop;

      print('-- Checking if Not minimized');
      expect(mainWindow.isMinimized, isFalse);

      // Process messages for 2s to show restore:
      await Window.runMessageLoopAsync(timeout: Duration(seconds: 2));
    }

    {
      print('-- Window.runMessageLoopAsync [destroy()]...');
      expect(receivedOnDestroyed, isFalse);

      var msgLoop = Window.runMessageLoopAsync(
          timeout: Duration(seconds: 3),
          condition: () => !mainWindow.isDestroyed);

      expect(receivedOnDestroyed, isFalse);
      mainWindow.destroy();

      print('-- Waiting: Window.runMessageLoopAsync [destroy()]...');
      await msgLoop;

      print('-- Checking `mainWindow.isDestroyed`');
      expect(mainWindow.isDestroyed, isTrue);
      expect(receivedOnDestroyed, isTrue);
    }

    // Ensure that the `test -c exe` exits:
    Future.delayed(Duration(seconds: 15), () {
      print('** Forcing exit(0).');
      Window.quit(0);
      exit(0);
    });

    print('-- Test finished.');
  });
}

class _MainWindow extends Window {
  // Declare the main window custom class:
  static final mainWindowClass = WindowClass.custom(
    className: 'mainWindow',
    windowProc: Pointer.fromFunction<WNDPROC>(mainWindowProc, 0),
    bgColor: RGB(255, 255, 255),
    useDarkMode: true,
    titleColor: RGB(32, 32, 32),
  );

  // Redirect to default implementation [WindowClass.windowProcDefault].
  static int mainWindowProc(int hwnd, int uMsg, int wParam, int lParam) =>
      WindowClass.windowProcDefault(
          hwnd, uMsg, wParam, lParam, mainWindowClass);

  late final _TextOutput textOutput;
  late final Button buttonOK;
  late final Button buttonExit;

  _MainWindow({super.width, super.height})
      : super(
          defaultRepaint: false,
          windowName: 'Win32 GUI - Example',
          windowClass: mainWindowClass,
          windowStyles: WINDOW_STYLE.WS_MINIMIZEBOX | WINDOW_STYLE.WS_SYSMENU,
        ) {
    textOutput =
        _TextOutput(parent: this, x: 4, y: 160, width: 626, height: 250);

    buttonOK = Button(
        label: 'OK',
        parent: this,
        x: 4,
        y: 414,
        width: 100,
        height: 32,
        onCommand: (w, l) => print('** Button OK Click!'));

    buttonExit = Button(
        label: 'Exit',
        parent: this,
        x: 106,
        y: 414,
        width: 100,
        height: 32,
        onCommand: (w, l) {
          print('** Button Exit Click!');
        });

    print(textOutput);
  }

  late final String imageDartLogoPath;
  late final String iconDartLogoPath;

  @override
  Future<void> load() async {
    imageDartLogoPath = await Window.resolveFilePath(
        'package:win32_gui/resources/dart-logo.bmp');

    print('-- imageDartLogoPath: $imageDartLogoPath');

    iconDartLogoPath = await Window.resolveFilePath(
        'package:win32_gui/resources/dart-icon.ico');
  }

  @override
  void build(int hwnd, int hdc) {
    super.build(hwnd, hdc);

    SetTextColor(hdc, RGB(255, 255, 255));
    SetBkColor(hdc, RGB(96, 96, 96));

    setIcon(iconDartLogoPath);
  }

  @override
  void repaint(int hwnd, int hdc) {
    var hBitmap = Window.loadImageCached(imageDartLogoPath);
    var imgDimension = Window.getBitmapDimension(hBitmap);

    // Valid Bitmap:
    if (imgDimension != null) {
      var imgW = imgDimension.width;
      var imgH = imgDimension.height;

      final hSpace = (dimensionWidth - imgW);
      //final vSpace = (dimensionHeight - imgH);
      final xCenter = hSpace ~/ 2;
      //final yCenter = vSpace ~/ 2;

      final x = xCenter;
      final y = 10;

      drawImage(hdc, hBitmap, x, y, imgW, imgH);
    }

    textOutput.callRepaint();
  }
}

class _TextOutput extends RichEdit {
  _TextOutput({super.parent, super.x, super.y, super.width, super.height})
      : super(bgColor: RGB(32, 32, 32));

  @override
  void build(int hwnd, int hdc) {
    super.build(hwnd, hdc);

    setBkColor(RGB(32, 32, 32));
    setTextColor(hdc, RGB(255, 255, 255));

    setAutoURLDetect(true);
  }

  @override
  void repaint(int hwnd, int hdc) {
    invalidateRect();

    setBkColor(RGB(32, 32, 32));
    setTextColor(hdc, RGB(255, 255, 255));

    setTextFormatted([
      TextFormatted(" -------------------------\r\n",
          color: RGB(255, 255, 255)),
      TextFormatted(" Hello", color: RGB(0, 255, 255)),
      TextFormatted(" Word! \r\n", color: RGB(0, 255, 0)),
      TextFormatted(" -------------------------\r\n",
          color: RGB(255, 255, 255)),
    ]);
  }
}
