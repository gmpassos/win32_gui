import 'dart:collection';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:resource_portable/resource.dart';
import 'package:win32/win32.dart';

import 'win32_constants.dart';

final _logWindow = logging.Logger('Win32:Window');

final hInstance = GetModuleHandle(nullptr);

typedef WindowProcFunction = int Function(
    int hwnd, int uMsg, int wParam, int lParam);

class WindowClassColors {
  final int? textColor;

  final int? bgColor;

  WindowClassColors({this.textColor, this.bgColor});

  @override
  String toString() {
    return 'WindowClassColors{textColor: $textColor, bgColor: $bgColor}';
  }
}

class WindowClass {
  static int? _loadedRichEditLibrary;

  static int loadRichEditLibrary() =>
      _loadedRichEditLibrary ??= _loadRichEditLibraryImpl();

  static int _loadRichEditLibraryImpl() {
    try {
      DynamicLibrary.open('RICHED20.DLL');
      return 2;
    } catch (_) {}

    try {
      DynamicLibrary.open('RICHED32.DLL');
      return 1;
    } catch (_) {}

    return 0;
  }

  final String className;
  final Pointer<NativeFunction<WindowProc>> windowProc;

  final bool isFrame;

  final int? bgColor;

  final bool useDarkMode;

  final int? titleColor;

  final bool custom;

  WindowClass.custom(
      {required this.className,
      required this.windowProc,
      this.isFrame = true,
      this.bgColor,
      this.useDarkMode = false,
      this.titleColor})
      : custom = true;

  WindowClass.predefined({required this.className, this.bgColor})
      : custom = false,
        windowProc = nullptr,
        isFrame = false,
        useDarkMode = false,
        titleColor = null;

  Pointer<Utf16>? _classNameNative;

  Pointer<Utf16> get classNameNative =>
      _classNameNative ??= className.toNativeUtf16();

  static WindowClassColors? staticColors;

  static WindowClassColors? editColors;

  static WindowClassColors? scrollBarColors;

  static int windowProcDefault(
      int hwnd, int uMsg, int wParam, int lParam, WindowClass windowClass) {
    var result = 0;

    // var name = Win32Constants.wmByID[uMsg];
    // print('winProc[default]> uMsg: $uMsg ; name: $name');

    _logWindow.info(
        'windowProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam, windowClass: ${windowClass.className}');

    switch (uMsg) {
      case WM_CREATE:
        {
          final hdc = GetDC(hwnd);

          if (windowClass.useDarkMode) {
            DwmSetWindowAttribute(
                hwnd,
                DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE,
                malloc<BOOL>()..value = 1,
                sizeOf<BOOL>());
          }

          final titleColor = windowClass.titleColor;
          if (titleColor != null) {
            DwmSetWindowAttribute(
              hwnd,
              DWMWINDOWATTRIBUTE.DWMWA_CAPTION_COLOR,
              malloc<COLORREF>()..value = titleColor,
              sizeOf<COLORREF>(),
            );
          }

          for (var w in windowClass._windows) {
            if (w._hwnd == hwnd) {
              w.callBuild(hdc: hdc);
            }
          }

          ReleaseDC(hwnd, hdc);
        }
      case WM_PAINT:
        {
          final ps = calloc<PAINTSTRUCT>();
          final hdc = BeginPaint(hwnd, ps);

          for (var w in windowClass._windows) {
            if (w._hwnd == hwnd) {
              w.callRepaint(hdc: hdc);
            }
          }

          EndPaint(hwnd, ps);
          free(ps);
        }
      case WM_COMMAND:
        {
          for (var w in windowClass._windows) {
            final hdc = GetDC(hwnd);
            w.processCommand(hwnd, hdc, lParam);
            ReleaseDC(hwnd, hdc);
          }
        }

      case WM_CTLCOLORSTATIC:
        {
          result = _setColors(wParam, staticColors);
        }
      case WM_CTLCOLOREDIT:
        {
          result = _setColors(wParam, editColors);
        }
      case WM_CTLCOLORSCROLLBAR:
        {
          result = _setColors(wParam, scrollBarColors);
        }
      case WM_DESTROY:
        {
          PostQuitMessage(0);
        }

      default:
        {
          result = DefWindowProc(hwnd, uMsg, wParam, lParam);
        }
    }

    return result;
  }

  static int _setColors(int hdc, WindowClassColors? colors) {
    if (colors == null) {
      return 0;
    }

    var textColor = colors.textColor;
    if (textColor != null) {
      SetTextColor(hdc, textColor);
    }

    var bgColor = colors.bgColor;
    if (bgColor != null) {
      SetBkMode(hdc, OPAQUE);
      SetBkColor(hdc, bgColor);
    }

    return CreateSolidBrush(bgColor ?? textColor ?? RGB(255, 255, 255));
  }

  final Set<Window> _windows = {};

  Set<Window> get windows => UnmodifiableSetView(_windows);

  bool registerWindow(Window window) => _windows.add(window);

  bool unregisterWindow(Window window) => _windows.remove(window);

  bool? _registered;

  bool get isRegisteredOK => _registered ?? false;

  bool register() => _registered ??= _registerWindowClass(this);

  static final Map<String, int> _registeredWindowClasses = {};

  static bool _registerWindowClass(WindowClass windowClass) {
    if (!windowClass.custom) {
      return true;
    }

    if (_registeredWindowClasses.containsKey(windowClass.className)) {
      return false;
    }

    final wc = calloc<WNDCLASS>();

    var wcRef = wc.ref;

    wcRef
      ..hInstance = hInstance
      ..lpszClassName = windowClass.classNameNative
      ..lpfnWndProc = windowClass.windowProc
      ..style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC
      ..hCursor = LoadCursor(NULL, IDC_ARROW);

    if (windowClass.isFrame) {
      wcRef.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    }

    final bgColor = windowClass.bgColor;
    if (bgColor != null) {
      wcRef.hbrBackground = CreateSolidBrush(bgColor);
    }

    var id = RegisterClass(wc);

    _registeredWindowClasses[windowClass.className] = id;

    return true;
  }

  @override
  String toString() {
    return 'WindowClass{className: $className, bgColor: $bgColor, useDarkMode: $useDarkMode, titleColor: $titleColor, windows: ${_windows.length}';
  }
}

class Window {
  static void runMessageLoop() {
    final msg = calloc<MSG>();
    while (GetMessage(msg, NULL, 0, 0) != 0) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
  }

  static Future<Uri> resolveFileUri(String path) => Resource(path).uriResolved;

  static Future<String> resolveFilePath(String path) =>
      resolveFileUri(path).then((uri) => uri.toFilePath());

  final WindowClass windowClass;
  final String? windowName;

  final int windowStyles;

  int? x;
  int? y;
  int? width;
  int? height;

  int? bgColor;

  bool get created => _hwnd != null;

  int? _hwnd;

  int get hwnd {
    final hwnd = _hwnd;
    if (hwnd == null) {
      throw StateError("Window not created! `hwnd` not defined.");
    }
    return hwnd;
  }

  int? get hwndIfCreated => _hwnd;

  final int? hMenu;
  final Window? parent;

  Window(
      {required this.windowClass,
      this.windowName,
      this.windowStyles = 0,
      this.x,
      this.y,
      this.width,
      this.height,
      this.bgColor,
      this.hMenu,
      this.parent}) {
    windowClass.register();

    create();

    windowClass.registerWindow(this);

    parent?._addChild(this);
  }

  Pointer<Utf16>? _windowNameNative;

  Pointer<Utf16> get windowNameNative =>
      _windowNameNative ??= windowName?.toNativeUtf16() ?? nullptr;

  int create() {
    final hwnd = CreateWindowEx(
        // Optional window styles:
        0,

        // Window class:
        windowClass.classNameNative,

        // Window text:
        windowNameNative,

        // Window style:
        windowStyles,

        // Size and position:
        x ?? CW_USEDEFAULT,
        y ?? CW_USEDEFAULT,
        width ?? CW_USEDEFAULT,
        height ?? CW_USEDEFAULT,

        // Parent window:
        parent?._hwnd ?? NULL,
        // Menu:
        hMenu ?? NULL,
        // Instance handle:
        hInstance,
        // Additional application data:
        nullptr);

    if (hwnd == 0) {
      var errorCode = GetLastError();
      throw StateError("Can't create window> errorCode: $errorCode -> $this");
    }

    _hwnd = hwnd;
    updateWindow();

    return hwnd;
  }

  final List<Window> _children = [];

  List<Window> get children => UnmodifiableListView(_children);

  void _addChild(Window child) {
    if (_children.contains(child)) {
      throw StateError("Child already added: $child");
    }

    print('-- Add child: $this -> $child');

    _children.add(child);
  }

  Future<void>? _loadCall;

  Future<void> ensureLoaded() => _loadCall ??= _callLoad();

  Future<void> _callLoad() async {
    print('-- _callLoad> $this');

    await load();

    print('-- Loaded> $this');

    for (var child in _children) {
      print('-- Loading child> $child');

      await child.ensureLoaded();
    }
  }

  /// Loads asynchronous resources.
  /// - Do not call directly, use [ensureLoaded].
  /// - Note that Win32 API [build] and [repaint] won't allow any asynchronous call ([Future]s).
  Future<void> load() async {}

  bool callBuild({int? hdc}) {
    ensureLoaded();
    final hwnd = this.hwnd;

    if (hdc == null) {
      final hdc = GetDC(hwnd);
      _callBuildImpl(hwnd, hdc);
      ReleaseDC(hwnd, hdc);
    } else {
      _callBuildImpl(hwnd, hdc);
    }

    return true;
  }

  void _callBuildImpl(int hwnd, int hdc) {
    fetchDimension();
    build(hwnd, hdc);
  }

  void build(int hwnd, int hdc) {
    SetMapMode(hdc, MM_ISOTROPIC);
    SetViewportExtEx(hdc, 1, 1, nullptr);
    SetWindowExtEx(hdc, 1, 1, nullptr);
  }

  bool callRepaint({int? hdc}) {
    ensureLoaded();

    final hwnd = this.hwnd;

    if (hdc == null) {
      final ps = calloc<PAINTSTRUCT>();
      final hdc = BeginPaint(hwnd, ps);

      _callRepaintImpl(hwnd, hdc);
      EndPaint(hwnd, ps);
    } else {
      _callRepaintImpl(hwnd, hdc);
    }

    return true;
  }

  void _callRepaintImpl(int hwnd, int hdc) {
    fetchDimension();
    repaint(hwnd, hdc);
  }

  void repaint(int hwnd, int hdc) {
    drawBG(hdc);
  }

  int sendMessage(int msg, int wParam, int lParam) {
    final hwnd = this.hwnd;
    return SendMessage(hwnd, msg, wParam, lParam);
  }

  final dimension = calloc<RECT>();

  void fetchDimension() {
    final hwnd = this.hwnd;
    GetClientRect(hwnd, dimension);
  }

  int get dimensionWidth => dimension.ref.right - dimension.ref.left;

  int get dimensionHeight => dimension.ref.bottom - dimension.ref.top;

  bool updateWindow() => UpdateWindow(hwnd) == 1;

  void show() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_SHOWNORMAL);
    updateWindow();
  }

  void drawBG(int hdc) {
    final bgColor = this.bgColor;

    if (bgColor != null) {
      fillRect(hdc, bgColor, pRect: dimension);
    }
  }

  final _rect = calloc<RECT>();

  void fillRect(int hdc, int color,
      {math.Rectangle? rect, Pointer<RECT>? pRect}) {
    Pointer<RECT>? r;

    if (rect != null) {
      _rect.ref
        ..top = rect.top.toInt()
        ..right = rect.right.toInt()
        ..bottom = rect.bottom.toInt()
        ..left = rect.left.toInt();

      r = _rect;
    } else if (pRect != null) {
      r = pRect;
    }

    if (r != null) {
      final hBrush = CreateSolidBrush(color);
      FillRect(hdc, r, hBrush);
      DeleteObject(hBrush);
    }
  }

  int getWindowTextLength() => GetWindowTextLength(hwnd);

  String getWindowText({int? length}) {
    length ??= getWindowTextLength();
    final strPtr = wsalloc(length + 1);
    GetWindowText(hwnd, strPtr, length + 1);
    final str = strPtr.toDartString();
    return str;
  }

  bool setWindowText(String text) =>
      SetWindowText(hwnd, text.toNativeUtf16()) != 0;

  void drawText(int hdc, String text, int x, int y) {
    final s = text.toNativeUtf16();
    TextOut(hdc, x, y, s, text.length);
    free(s);
  }

  final Map<String, int> _imagesCached = {};

  int loadImageCached(String imgPath, int imgWidth, int imgHeight) {
    return _imagesCached[imgPath] ??= loadImage(imgPath, imgWidth, imgHeight);
  }

  int loadImage(String imgPath, int imgWidth, int imgHeight) {
    final hBitmap = LoadImage(NULL, imgPath.toNativeUtf16(), IMAGE_BITMAP,
        imgWidth, imgHeight, LR_LOADFROMFILE);

    return hBitmap;
  }

  void drawImage(int hdc, int hBitmap, int x, int y, int width, int height) {
    final hMemDC = CreateCompatibleDC(hdc);

    SelectObject(hMemDC, hBitmap);

    BitBlt(hdc, x, y, width, height, hMemDC, 0, 0, SRCCOPY);

    DeleteObject(hMemDC);
  }

  void setIcon(String iconPath, {bool small = true, bool big = true}) {
    var iconPathPtr = iconPath.toNativeUtf16();

    if (small) {
      var hIcon =
          LoadImage(NULL, iconPathPtr, IMAGE_ICON, 16, 16, LR_LOADFROMFILE);
      sendMessage(WM_SETICON, ICON_SMALL, hIcon);
    }

    if (big) {
      var hIcon =
          LoadImage(NULL, iconPathPtr, IMAGE_ICON, 32, 32, LR_LOADFROMFILE);
      sendMessage(WM_SETICON, ICON_BIG, hIcon);
    }
  }

  void processCommand(int hwnd, int hdc, int lParam) {
    for (var child in _children) {
      if (child._hwnd == lParam) {
        child.processCommand(hwnd, hdc, lParam);
      }
    }
  }

  @override
  String toString() {
    return 'Window#$_hwnd{windowName: $windowName, windowStyles: $windowStyles, x: $x, y: $y, width: $width, height: $height, bgColor: $bgColor, parent: $parent}@$windowClass';
  }
}

class ChildWindow extends Window {
  static int idCount = 0;

  static int newID() => ++idCount;

  int get id => hMenu!;

  ChildWindow(
      {int? id,
      required super.windowClass,
      super.windowName,
      super.windowStyles = 0,
      super.x,
      super.y,
      super.width,
      super.height,
      super.bgColor,
      required super.parent})
      : super(hMenu: id ?? newID());
}
