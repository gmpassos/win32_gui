import 'package:win32_gui/win32_gui.dart';

Future<void> main() async {
  var editorClass = WindowClassColors(
    textColor: RGB(0, 0, 0),
    bgColor: RGB(128, 128, 128),
  );

  WindowClass.editColors = editorClass;
  WindowClass.staticColors = editorClass;

  var mainWindow = MainWindow(
    width: 640,
    height: 480,
  );

  print('-- mainWindow.ensureLoaded...');
  await mainWindow.ensureLoaded();

  print('-- mainWindow.show...');
  mainWindow.show();

  print('-- Window.runMessageLoop...');
  Window.runMessageLoop();
}

class MainWindow extends Window {
  // Declare the main window custom class:
  static final mainWindowClass = WindowClass.custom(
    className: 'mainWindow',
    windowProc: Pointer.fromFunction<WindowProc>(mainWindowProc, 0),
    bgColor: RGB(255, 255, 255),
    useDarkMode: true,
    titleColor: RGB(32, 32, 32),
  );

  // Redirect to default implementation [WindowClass.windowProcDefault].
  static int mainWindowProc(int hwnd, int uMsg, int wParam, int lParam) =>
      WindowClass.windowProcDefault(
          hwnd, uMsg, wParam, lParam, mainWindowClass);

  late final TextOutput textOutput;
  late final Button buttonOK;
  late final Button buttonExit;

  MainWindow({super.width, super.height})
      : super(
          windowName: 'Main Window',
          windowClass: mainWindowClass,
          windowStyles: WS_MINIMIZEBOX | WS_SYSMENU,
        ) {
    textOutput =
        TextOutput(parent: this, x: 4, y: 160, width: 626, height: 250);

    buttonOK =
        Button(label: 'OK', parent: this, x: 4, y: 414, width: 100, height: 32);
    buttonExit = Button(
        label: 'Exit', parent: this, x: 106, y: 414, width: 100, height: 32);

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

    // Some extra build...
  }

  @override
  void repaint(int hwnd, int hdc) {
    super.repaint(hwnd, hdc);

    setIcon(hwnd, iconDartLogoPath);

    var imgW = 143;
    var imgH = 139;

    var hBitmap = loadImageCached(hwnd, imageDartLogoPath, imgW, imgH);

    final hSpace = (dimensionWidth - imgW);
    //final vSpace = (dimensionHeight - imgH);
    final xCenter = hSpace ~/ 2;
    //final yCenter = vSpace ~/ 2;

    final x = xCenter;
    final y = 10;

    drawImage(hwnd, hdc, hBitmap, x, y, imgW, imgH);

    textOutput.callRepaint();
  }
}

class TextOutput extends RichEdit {
  TextOutput({super.parent, super.x, super.y, super.width, super.height});

  @override
  void repaint(int hwnd, int hdc) {
    SetTextColor(hdc, RGB(0, 255, 0));
    setBkColor(hwnd, RGB(16, 16, 16));
    setAutoURLDetect(hwnd, true);

    appendText(hwnd, RGB(255, 255, 255), "-------------------------\r\n");
    appendText(hwnd, RGB(0, 0, 255), "Hello ");
    appendText(hwnd, RGB(0, 255, 0), "Word!\r\n ");
    appendText(hwnd, RGB(255, 255, 255), "-------------------------\r\n");
  }
}
