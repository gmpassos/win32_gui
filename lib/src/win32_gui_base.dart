import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:resource_portable/resource.dart';
import 'package:win32/win32.dart';

import 'win32_constants.dart';

final _logWindow = logging.Logger('Win32:Window');

final hInstance = GetModuleHandle(nullptr);

/// A [WindowProc] function.
/// - It's passed to a [RegisterClass] call.
typedef WindowProcFunction = int Function(
    int hwnd, int uMsg, int wParam, int lParam);

/// Defines the colors of a [Window].
class WindowClassColors {
  /// The text color.
  final int? textColor;

  /// The background color.
  final int? bgColor;

  WindowClassColors({this.textColor, this.bgColor});

  @override
  String toString() {
    return 'WindowClassColors{textColor: $textColor, bgColor: $bgColor}';
  }
}

/// A [Window] class.
class WindowClass {
  /// The class name of this [Window] Class.
  final String className;

  /// The pointer to the [WindowProc].
  /// See [WindowClass.windowProcDefault].
  final Pointer<NativeFunction<WindowProc>> windowProc;

  /// Return `true` if this is a frame window, `false` if it's a child component.
  final bool isFrame;

  /// The background color of the window.
  final int? bgColor;

  /// If `true` set's this [Window] frame to dark mode.
  final bool useDarkMode;

  /// The tile color of this [Window] frame.
  final int? titleColor;

  /// If `true` and uses [windowProcDefault], it will call [getWindowWithHWnd]
  /// passing `global: true`.
  final bool lookupWindowGlobally;

  /// Returns `true` if it's a custom [WindowClass].
  final bool custom;

  /// Creates a custom [WindowClass].
  WindowClass.custom(
      {required this.className,
      required this.windowProc,
      this.isFrame = true,
      this.bgColor,
      this.useDarkMode = false,
      this.titleColor,
      this.lookupWindowGlobally = true})
      : custom = true;

  WindowClass._predefined(this.className, this.bgColor)
      : custom = false,
        windowProc = nullptr,
        isFrame = false,
        useDarkMode = false,
        titleColor = null,
        lookupWindowGlobally = false;

  static final Map<String, WindowClass> _predefinedClasses = {};

  /// Returns a pre-defined [WindowClass].
  /// - Returns the same instances for each [className].
  factory WindowClass.predefined({required String className, int? bgColor}) {
    return _predefinedClasses[className] ??=
        WindowClass._predefined(className, bgColor);
  }

  Pointer<Utf16>? _classNameNative;

  Pointer<Utf16> get classNameNative =>
      _classNameNative ??= className.toNativeUtf16();

  /// Defines the colors for `WM_CTLCOLORSTATIC` message.
  static WindowClassColors? staticColors;

  /// Defines the colors for `WM_CTLCOLOREDIT` message.
  static WindowClassColors? editColors;

  /// Defines the colors for `WM_CTLCOLORSCROLLBAR` message.
  static WindowClassColors? scrollBarColors;

  /// A default implementation of a [windowProc] function associated with a [windowClass].
  static int windowProcDefault(
      int hwnd, int uMsg, int wParam, int lParam, WindowClass windowClass) {
    var result = 0;

    // var name = Win32Constants.wmByID[uMsg];
    // print('winProc[default]> uMsg: $uMsg ; name: $name');

    _logWindow.info(
        'windowProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam, windowClass: ${windowClass.className}');

    final windowGlobal = windowClass.lookupWindowGlobally;
    Window? window;

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

          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            window.callBuild(hdc: hdc);
          }

          ReleaseDC(hwnd, hdc);
        }
      case WM_PAINT:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            final ps = calloc<PAINTSTRUCT>();
            final hdc = BeginPaint(hwnd, ps);

            window.callRepaint(hdc: hdc);

            EndPaint(hwnd, ps);
            free(ps);
          }
        }
      case WM_COMMAND:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            final hdc = GetDC(hwnd);
            window.processCommand(hwnd, hdc, lParam);
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
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          window?.processDestroy(wParam, lParam);
        }
      case WM_NCDESTROY:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          window?._notifyDestroyed();
        }
      default:
        {
          int? processed;

          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            processed = window.processMessage(hwnd, uMsg, wParam, lParam);
          }

          if (processed != null) {
            result = processed;
          } else {
            result = DefWindowProc(hwnd, uMsg, wParam, lParam);
          }
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

  static final Set<Window> _allWindows = {};

  /// Returns all registered [Window] instances.
  static Set<Window> get allWindows => UnmodifiableSetView(_allWindows);

  final Set<Window> _windows = {};

  /// Returns the [Window] instances registered with this [WindowClass].
  Set<Window> get windows => UnmodifiableSetView(_windows);

  /// Returns a [Window] with [hwnd] that was registered with this [WindowClass].
  /// - See [windows].
  /// - If [global] is `true` also looks at [allWindows].
  Window? getWindowWithHWnd(int hwnd, {bool global = false}) {
    var w = _windows.firstWhereOrNull((w) => w._hwnd == hwnd);
    if (w == null && global) {
      w = _allWindows.firstWhereOrNull((w) => w._hwnd == hwnd);
    }
    return w;
  }

  /// Registers a [window] with this [WindowClass].
  /// - Called by [Window] constructor.
  bool registerWindow(Window window) {
    _allWindows.add(window);
    return _windows.add(window);
  }

  /// Unregisters a [window] with this [WindowClass].
  /// - Called after [Window.onDestroy].
  bool unregisterWindow(Window window) {
    _allWindows.remove(window);
    return _windows.remove(window);
  }

  bool? _registered;

  /// Returns `true` of this class was successfully registered.
  bool get isRegisteredOK => _registered ?? false;

  /// Registers this class.
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

/// The [Window] message loop implementation.
class WindowMessageLoop {
  /// Runs a [Window] message loop that blocks the current thread/`Isolate`.
  ///
  /// - If [condition] is passed loops while [condition] is `true`.
  /// - Uses Win32 [GetMessage] to consume the [Window] messages (blocking call).
  /// - See [runLoopAsync].
  static void runLoop({bool Function()? condition}) {
    condition ??= () => true;

    final msg = calloc<MSG>();

    while (condition() && GetMessage(msg, NULL, 0, 0) != 0) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
  }

  static const yieldMS1 = Duration(milliseconds: 1);
  static const yieldMS10 = Duration(milliseconds: 10);
  static const yieldMS30 = Duration(milliseconds: 30);
  static const yieldMS100 = Duration(milliseconds: 100);

  /// Runs a [Window] message loop capable to [timeout] and also
  /// allows Dart [Future]s to be processed while processing messages.
  ///
  /// - If [condition] is passed loops while [condition] is `true`.
  /// - Uses Win32 [PeekMessage] to consume the [Window] messages (non-blocking call).
  /// - See [runLoop].
  static Future<int> runLoopAsync(
      {Duration? timeout,
      int maxConsecutiveDispatches = 100,
      bool Function()? condition}) async {
    maxConsecutiveDispatches = maxConsecutiveDispatches.clamp(2, 1000);
    condition ??= () => true;

    final initTime = DateTime.now();

    final msg = calloc<MSG>();

    var totalMsgCount = 0;
    var noMsgCount = 0;
    var msgCount = 0;

    while (condition()) {
      var got = PeekMessage(msg, NULL, 0, 0, 1);

      if (got != 0) {
        totalMsgCount++;
        noMsgCount = 0;
        ++msgCount;

        TranslateMessage(msg);
        DispatchMessage(msg);

        if (msgCount > 0 && msgCount % maxConsecutiveDispatches == 0) {
          if (initTime.timeOut(timeout)) break;

          await Future.delayed(yieldMS1);
        }
      } else {
        ++noMsgCount;
        msgCount = 0;

        if (noMsgCount > 1) {
          if (initTime.timeOut(timeout)) break;

          var yieldMS = switch (noMsgCount) {
            > 1000 => yieldMS100,
            > 30 => yieldMS30,
            > 10 => yieldMS10,
            _ => yieldMS1,
          };

          await Future.delayed(yieldMS);
        }
      }
    }

    return totalMsgCount;
  }
}

extension _DateTimeExtension on DateTime {
  Duration get elapsedTime => DateTime.now().difference(this);

  Duration remainingTime(Duration timeout) => timeout - elapsedTime;

  bool hasRemainingTime(Duration? timeout) {
    if (timeout == null) return true;
    return remainingTime(timeout).inMilliseconds > 0;
  }

  bool timeOut(Duration? timeout) => !hasRemainingTime(timeout);
}

/// A Win32 Window.
/// - See [ChildWindow].
class Window {
  /// Alias to [WindowMessageLoop.runLoop].
  static void runMessageLoop({bool Function()? condition}) =>
      WindowMessageLoop.runLoop(condition: condition);

  /// Alias to [WindowMessageLoop.runLoopAsync].
  static Future<int> runMessageLoopAsync(
          {Duration? timeout,
          int maxConsecutiveDispatches = 100,
          bool Function()? condition}) =>
      WindowMessageLoop.runLoopAsync(
          timeout: timeout,
          maxConsecutiveDispatches: maxConsecutiveDispatches,
          condition: condition);

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

  /// Calls [build] resolving necessary parameters.
  /// - Used by [WindowClass.windowProcDefault].
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

  /// [Window] build procedure.
  void build(int hwnd, int hdc) {
    SetMapMode(hdc, MM_ISOTROPIC);
    SetViewportExtEx(hdc, 1, 1, nullptr);
    SetWindowExtEx(hdc, 1, 1, nullptr);
  }

  /// Calls [repaint] resolving necessary parameters.
  /// - Used by [WindowClass.windowProcDefault].
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

  /// [Window] repaint procedure.
  void repaint(int hwnd, int hdc) {
    drawBG(hdc);
  }

  /// Sends a [message] to this [Window].
  int sendMessage(int message, int wParam, int lParam) {
    final hwnd = this.hwnd;
    return SendMessage(hwnd, message, wParam, lParam);
  }

  /// This [Window] dimension (with the last fetch value).
  /// - See: [fetchDimension], [dimensionWidth], [dimensionHeight].
  final dimension = calloc<RECT>();

  /// Fetches this [Window] [dimension].
  void fetchDimension() {
    final hwnd = this.hwnd;
    GetClientRect(hwnd, dimension);
  }

  /// This [dimension] width.
  int get dimensionWidth => dimension.ref.right - dimension.ref.left;

  /// This [dimension] height.
  int get dimensionHeight => dimension.ref.bottom - dimension.ref.top;

  /// Updates this [Window].
  /// - Calls Win32 [UpdateWindow].
  bool updateWindow() => UpdateWindow(hwnd) == 1;

  /// Shows this [Window].
  /// - Calls Win32 [ShowWindow].
  void show() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_SHOWNORMAL);
    updateWindow();
  }

  /// Closes this [Window].
  /// - Calls Win32 [CloseWindow].
  void close() {
    ensureLoaded();
    final hwnd = this.hwnd;

    CloseWindow(hwnd);
  }

  /// Destroys this [Window].
  /// - Calls Win32 [DestroyWindow].
  void destroy() {
    ensureLoaded();
    final hwnd = this.hwnd;

    DestroyWindow(hwnd);
  }

  /// Sends quit message with [exitCode].
  /// - Calls Win32 [PostQuitMessage].
  void quit([int exitCode = 0]) {
    PostQuitMessage(exitCode);
  }

  /// Paint operation: draws this [Window] background.
  void drawBG(int hdc, {int? bgColor}) {
    bgColor ??= this.bgColor;

    if (bgColor != null) {
      fillRect(hdc, bgColor, pRect: dimension);
    }
  }

  final _rect = calloc<RECT>();

  /// Paint operation: fills a rectangle with [color].
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

  /// Returns this [Window] text length.
  /// - Calls Win32 [GetWindowTextLength].
  /// - See [getWindowText].
  int getWindowTextLength() => GetWindowTextLength(hwnd);

  /// Returns this [Window] text.
  /// - Calls Win32 [getWindowTextLength] and [GetWindowText].
  /// - See [getWindowTextLength].
  String getWindowText({int? length}) {
    length ??= getWindowTextLength();
    final strPtr = wsalloc(length + 1);
    GetWindowText(hwnd, strPtr, length + 1);
    final str = strPtr.toDartString();
    return str;
  }

  /// Sets this [Window] text.
  /// - Calls Win32 [SetWindowText].
  /// - See [getWindowText].
  bool setWindowText(String text) =>
      SetWindowText(hwnd, text.toNativeUtf16()) != 0;

  /// Paint operation: draws [text] at coordinates [x], [y].
  void drawText(int hdc, String text, int x, int y) {
    final s = text.toNativeUtf16();
    TextOut(hdc, x, y, s, text.length);
    free(s);
  }

  final Map<String, int> _imagesCached = {};

  /// Cached version of [loadImage].
  int loadImageCached(String imgPath, int imgWidth, int imgHeight) {
    return _imagesCached[imgPath] ??= loadImage(imgPath, imgWidth, imgHeight);
  }

  /// Loads image from [imgPath] with dimension [imgWidth], [imgHeight].
  /// - The image should be a 24bit Bitmap.
  /// - See [loadImageCached].
  int loadImage(String imgPath, int imgWidth, int imgHeight) {
    final hBitmap = LoadImage(NULL, imgPath.toNativeUtf16(), IMAGE_BITMAP,
        imgWidth, imgHeight, LR_LOADFROMFILE);

    return hBitmap;
  }

  /// Paint operation: draws [hBitmap] at coordinates [x], [y].
  void drawImage(int hdc, int hBitmap, int x, int y, int width, int height) {
    final hMemDC = CreateCompatibleDC(hdc);

    SelectObject(hMemDC, hBitmap);

    BitBlt(hdc, x, y, width, height, hMemDC, 0, 0, SRCCOPY);

    DeleteObject(hMemDC);
  }

  /// Sets this [Window] icon from [iconPath].
  ///
  /// - If [small] is true, sets a 16x16 icon.
  /// - If [big] is true, sets a 32x32 icon.
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

  /// Processes a [WM_COMMAND] message. Also calls [processCommand] for [children] [Window]s.
  void processCommand(int hwnd, int hdc, int lParam) {
    for (var child in _children) {
      if (child._hwnd == lParam) {
        child.processCommand(hwnd, hdc, lParam);
      }
    }
  }

  /// Processes a [WM_DESTROY] message.
  void processDestroy(int wParam, int lParam) {}

  /// Processes a message.
  /// - Called by [WindowClass.windowProcDefault] when the messages doesn't have a default processor.
  /// - Should return a value if this messages was processed, or `null` to send to [DefWindowProc].
  int? processMessage(int hwnd, int uMsg, int wParam, int lParam) => null;

  final StreamController<Window> _onDestroy = StreamController();

  /// On destroy event (after [WM_DESTROY] -> [WM_NCDESTROY] messages).
  /// - Called by [WindowClass.windowProcDefault].
  Stream<Window> get onDestroy => _onDestroy.stream;

  bool _destroyed = false;

  /// Returns `true` if the window was [destroy]ed and the `WM_NCDESTROY` was processed.
  /// - See [onDestroy].
  bool get isDestroyed => _destroyed;

  void _notifyDestroyed() {
    _destroyed = true;

    _onDestroy.add(this);

    var waitingDestroyed = _waitingDestroyed;
    if (waitingDestroyed != null && !waitingDestroyed.isCompleted) {
      waitingDestroyed.complete(true);
      _waitingDestroyed = null;
    }

    windowClass.unregisterWindow(this);
  }

  Completer<bool>? _waitingDestroyed;

  /// Waits for this window to be destroyed.
  /// - If [timeout] is defined it will return `false` on timeout.
  Future<bool> waitDestroyed({Duration? timeout}) {
    if (_destroyed) return Future.value(true);

    var waitingDestroyed = _waitingDestroyed ??= Completer();

    var future = waitingDestroyed.future;

    if (timeout != null) {
      future = future.timeout(timeout, onTimeout: () => false);
    }

    return future;
  }

  @override
  String toString() {
    return 'Window#$_hwnd{windowName: $windowName, windowStyles: $windowStyles, x: $x, y: $y, width: $width, height: $height, bgColor: $bgColor, parent: $parent}@$windowClass';
  }
}

/// A Win32 Child [Window].
class ChildWindow extends Window {
  static int idCount = 0;

  /// Creates a new [id] of a [ChildWindow]. Called by [ChildWindow] constructor.
  static int newID() => ++idCount;

  /// Returns the ID of this child window.
  /// - Stored at [hMenu].
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
