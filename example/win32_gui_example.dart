import 'package:win32_gui/win32_gui.dart';

void main() {
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

  mainWindow.show();

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
    richEdit = RichEdit(parentHwnd: hwnd);
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

    final imgPath = r'C:\menuici\menuici-logo-24.bmp';
    var w = 512;
    var h = 512;

    var hBitmap = loadImageCached(hwnd, imgPath, w, h);

    final hSpace = (dimensionWidth - w);
    final vSpace = (dimensionHeight - h);
    final xCenter = hSpace ~/ 2;
    //final yCenter = vSpace ~/ 2;

    final x = xCenter;
    final y = vSpace;

    drawImage(hwnd, hdc, hBitmap, x, y, w, h);

    richEdit.callRepaint();
  }
}
