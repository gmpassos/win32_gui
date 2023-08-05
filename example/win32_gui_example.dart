import 'package:win32_gui/win32_gui.dart';

Future<void> main() async {
  var editorClass = WindowClassColors(
    textColor: RGB(0, 0, 0),
    bgColor: RGB(255, 255, 255),
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
    bgColor: RGB(96, 96, 96),
    useDarkMode: true,
    titleColor: RGB(96, 96, 96),
  );

  // Redirect to default implementation [WindowClass.windowProcDefault].
  static int mainWindowProc(int hwnd, int uMsg, int wParam, int lParam) =>
      WindowClass.windowProcDefault(
          hwnd, uMsg, wParam, lParam, mainWindowClass);

  late final RichEdit richEdit;

  MainWindow({super.width, super.height})
      : super(
          windowName: 'Main Window',
          windowClass: mainWindowClass,
          windowStyles: WS_MINIMIZEBOX | WS_SYSMENU,
        ) {
    richEdit = RichEdit(parent: this);

    print(richEdit);
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

    setIcon(hwnd, iconDartLogoPath);
  }

  @override
  void repaint(int hwnd, int hdc) {
    super.repaint(hwnd, hdc);

    var imgW = 143;
    var imgH = 139;

    var hBitmap = loadImageCached(hwnd, imageDartLogoPath, imgW, imgH);

    final hSpace = (dimensionWidth - imgW);
    final vSpace = (dimensionHeight - imgH);
    final xCenter = hSpace ~/ 2;
    //final yCenter = vSpace ~/ 2;

    final x = xCenter;
    final y = vSpace;

    drawImage(hwnd, hdc, hBitmap, x, y, imgW, imgH);

    richEdit.callRepaint();
  }
}
