import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:resource_portable/resource.dart';
import 'package:win32/win32.dart';

import 'win32_constants.dart';
import 'win32_constants_extra.dart';

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

  /// Defines the colors for `WM_CTLCOLORBTN` message.
  static WindowClassColors? buttonColors;

  /// Defines the colors for `WM_CTLCOLORLISTBOX` message.
  static WindowClassColors? listBoxColors;

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
          if (window != null && !window.defaultRepaint) {
            final ps = calloc<PAINTSTRUCT>();
            final hdc = BeginPaint(hwnd, ps);

            window.callRepaint(hdc: hdc);

            EndPaint(hwnd, ps);
            free(ps);

            // Message processed (custom paint):
            result = 0;
          } else {
            // Message NOT processed (default paint):
            result = DefWindowProc(hwnd, uMsg, wParam, lParam);
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
      case WM_CTLCOLORBTN:
        {
          result = _setColors(wParam, buttonColors);
        }
      case WM_CTLCOLORLISTBOX:
        {
          result = _setColors(wParam, listBoxColors);
        }
      case WM_CTLCOLOREDIT:
        {
          result = _setColors(wParam, editColors);
        }
      case WM_CTLCOLORSCROLLBAR:
        {
          result = _setColors(wParam, scrollBarColors);
        }

      case WM_CLOSE:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            var shouldClose = window.processClose();
            window._notifyClose();

            if (shouldClose == null) {
              result = DefWindowProc(hwnd, uMsg, wParam, lParam);
            } else if (shouldClose) {
              if (!window.isMinimized) {
                window.minimize();
              }
              result = 0;
            } else {
              result = 0;
            }
          }
        }

      case WM_DESTROY:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            window.processDestroy();
            result = DefWindowProc(hwnd, uMsg, wParam, lParam);
          }
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
  /// - Called after [Window.onDestroyed].
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

  /// Resolves [path] to [Uri].
  /// - See [Resource].
  static Future<Uri> resolveFileUri(String path) => Resource(path).uriResolved;

  /// Resolves [path] to a local file path.
  /// - See [Resource].
  static Future<String> resolveFilePath(String path) =>
      resolveFileUri(path).then((uri) => uri.toFilePath());

  /// Returns the system fonts.
  /// - Calls [SystemParametersInfo] [SPI_GETNONCLIENTMETRICS].
  static Map<String, String> getSystemDefaultFonts() {
    var ncm = calloc<NONCLIENTMETRICS>();
    var ncmRef = ncm.ref;

    final ncmSz = sizeOf<NONCLIENTMETRICS>();
    ncmRef.cbSize = ncmSz;

    var ok = SystemParametersInfo(SPI_GETNONCLIENTMETRICS, ncmSz, ncm, 0) != 0;

    if (!ok) {
      var errorCode = GetLastError();
      throw StateError(
          "Can't call `SystemParametersInfo(SPI_GETNONCLIENTMETRICS...)`. Error: $errorCode");
    }

    var info = <String, String>{
      'caption': ncmRef.lfCaptionFont.lfFaceName,
      'menu': ncmRef.lfMenuFont.lfFaceName,
      'message': ncmRef.lfMessageFont.lfFaceName,
      'status': ncmRef.lfStatusFont.lfFaceName,
    };

    free(ncm);
    return info;
  }

  /// The [WindowClass] of this [Window].
  final WindowClass windowClass;

  /// The name of this [Window]. If it's a frame this is the [Window] title.
  final String? windowName;

  /// The style flags of this [Window] to pass to [CreateWindowEx].
  final int windowStyles;

  /// The [x] coordinate of this [Window] when created.
  int? x;

  /// The [y] coordinate of this [Window] when created.
  int? y;

  /// The [width] of this [Window] when created.
  int? width;

  /// The [height] of this [Window] when created.
  int? height;

  /// The background color of this [Window] (if applicable).
  int? bgColor;

  /// Returns `true` if this [Window] was created.
  bool get created => _hwnd != null;

  int? _hwnd;

  /// The window handler ID (if [created]).
  int get hwnd {
    final hwnd = _hwnd;
    if (hwnd == null) {
      throw StateError("Window not created! `hwnd` not defined.");
    }
    return hwnd;
  }

  /// Returns the window handler ID if [created] or `null`.
  int? get hwndIfCreated => _hwnd;

  /// The [hMenu] parameter passed to [CreateWindowEx].
  /// - If this is a [ChildWindow] this is the child element ID ([ChildWindow.id]).
  final int? hMenu;

  /// The parent [Window] of this instance.
  /// - See [ChildWindow].
  final Window? parent;

  /// If `true` will perform a default repaint and
  /// will NOT call the custom [repaint] method.
  bool defaultRepaint;

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
      required this.defaultRepaint,
      this.parent}) {
    windowClass.register();

    create();

    windowClass.registerWindow(this);

    parent?._addChild(this);
  }

  Pointer<Utf16>? _windowNameNative;

  Pointer<Utf16> get windowNameNative =>
      _windowNameNative ??= windowName?.toNativeUtf16() ?? nullptr;

  /// Creates this [Window] (called by constructor).
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

    if (defaultRepaint) {
      return false;
    }

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

  /// [Window] custom repaint procedure.
  /// - [defaultRepaint] should be `false` to call a custom [repaint].
  void repaint(int hwnd, int hdc) {}

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

  Pointer<RECT>? _resolveRect(math.Rectangle<num>? rect, Pointer<RECT>? pRect) {
    if (rect != null) {
      _rect.ref
        ..top = rect.top.toInt()
        ..right = rect.right.toInt()
        ..bottom = rect.bottom.toInt()
        ..left = rect.left.toInt();

      return _rect;
    } else if (pRect != null) {
      return pRect;
    } else {
      return null;
    }
  }

  /// Redraws this [Window].
  /// - Calls Win32 [RedrawWindow].
  bool redrawWindow({math.Rectangle? rect, Pointer<RECT>? pRect, int? flags}) {
    var r = _resolveRect(rect, pRect);
    flags ??= RDW_ALLCHILDREN | RDW_INVALIDATE | RDW_ERASE | RDW_UPDATENOW;
    return RedrawWindow(hwnd, r ?? nullptr, 0, flags) == 1;
  }

  /// Invalidates [Window] region.
  /// - Calls Win32 [InvalidateRect].
  bool invalidateRect(
      {math.Rectangle? rect, Pointer<RECT>? pRect, bool eraseBg = true}) {
    var r = _resolveRect(rect, pRect);
    return InvalidateRect(hwnd, r ?? nullptr, eraseBg ? 1 : 0) != 0;
  }

  /// Sets this [Window] rounded corners attributes.
  /// - If [rounded] is `true` will set this [Window] with rounded corners,
  ///   otherwise will disable the rounded corners.
  /// - If [small] is `true` round the corners with a small radius.
  void setWindowRoundedCorners({bool rounded = true, bool small = false}) {
    final pref = calloc<DWORD>();
    try {
      final hwnd = this.hwnd;

      final attr = DWMWINDOWATTRIBUTE.DWMWA_WINDOW_CORNER_PREFERENCE;
      pref.value = rounded
          ? (small
              ? DWM_WINDOW_CORNER_PREFERENCE.DWMWCP_ROUNDSMALL
              : DWM_WINDOW_CORNER_PREFERENCE.DWMWCP_ROUND)
          : DWM_WINDOW_CORNER_PREFERENCE.DWMWCP_DONOTROUND;

      DwmSetWindowAttribute(hwnd, attr, pref, sizeOf<DWORD>());
    } finally {
      free(pref);
    }
  }

  /// Shows this [Window].
  /// - Calls Win32 [ShowWindow] [SW_SHOWNORMAL].
  void show() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_SHOWNORMAL);
    updateWindow();
  }

  /// Minimizes this [Window].
  /// - Calls Win32 [ShowWindow] [SW_MINIMIZE].
  void minimize() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_MINIMIZE);
  }

  /// Maximized this [Window].
  /// - Calls Win32 [ShowWindow] [SW_MAXIMIZE].
  void maximize() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_MAXIMIZE);
    updateWindow();
  }

  /// Restores this [Window].
  /// - Calls Win32 [ShowWindow] [SW_RESTORE].
  void restore() {
    ensureLoaded();
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_RESTORE);
    updateWindow();
  }

  /// Returns if this [Window] is minimized.
  /// - See [getWindowLongPtr].
  bool get isMinimized => (getWindowLongPtr(GWL_STYLE) & WS_MINIMIZE) != 0;

  /// Returns if this [Window] is maximized.
  /// - See [getWindowLongPtr].
  bool get isMaximized => (getWindowLongPtr(GWL_STYLE) & WS_MAXIMIZE) != 0;

  int getWindowLongPtr(int nIndex) {
    ensureLoaded();
    final hwnd = this.hwnd;
    return GetWindowLongPtr(hwnd, nIndex);
  }

  /// Closes this [Window].
  /// - Calls Win32 [CloseWindow].
  /// - Returns `true` (closed) and calls [CloseWindow] if `processClose` returns `null` (delegates to default behavior).
  /// - Returns `false` (minimize) if `processClose` returns `true` (confirm close).
  /// - Returns `null` (do nothing) if `processClose` returns `false` (abort close).
  bool? close() {
    ensureLoaded();
    final hwnd = this.hwnd;

    var shouldClose = processClose();
    _notifyClose();

    if (shouldClose == null) {
      CloseWindow(hwnd);
      return true;
    } else if (shouldClose) {
      if (!isMinimized) {
        minimize();
      }
      return false;
    } else {
      return null;
    }
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
  static void quit([int exitCode = 0]) {
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
    var r = _resolveRect(rect, pRect);

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
  /// -- See [getBitmapDimension].
  int loadImageCached(String imgPath, {int imgWidth = 0, int imgHeight = 0}) =>
      _imagesCached[imgPath] ??=
          loadImage(imgPath, imgWidth: imgWidth, imgHeight: imgHeight);

  /// Loads image from [imgPath] with dimension [imgWidth], [imgHeight].
  /// - The image should be a 24bit Bitmap.
  /// - See [loadImageCached] and [getBitmapDimension].
  int loadImage(String imgPath, {int imgWidth = 0, int imgHeight = 0}) {
    final hBitmap = LoadImage(NULL, imgPath.toNativeUtf16(), IMAGE_BITMAP,
        imgWidth, imgHeight, LR_LOADFROMFILE);

    return hBitmap;
  }

  /// Returns the [hBitmap] dimension.
  /// - Calls [GetObject].
  ({int width, int height})? getBitmapDimension(int hBitmap) {
    var bm = calloc<BITMAP>();

    var ok = GetObject(hBitmap, sizeOf<BITMAP>(), bm) != 0;
    if (!ok) {
      free(bm);
      return null;
    }

    var dimension = (width: bm.ref.bmWidth, height: bm.ref.bmHeight);
    free(bm);

    return dimension;
  }

  /// Paint operation: draws [hBitmap] at coordinates [x], [y].
  void drawImage(int hdc, int hBitmap, int x, int y, int width, int height) {
    final hMemDC = CreateCompatibleDC(hdc);

    SelectObject(hMemDC, hBitmap);

    BitBlt(hdc, x, y, width, height, hMemDC, 0, 0, SRCCOPY);

    DeleteObject(hMemDC);
  }

  int? _iconSmall;
  int? _iconBig;

  /// Sets this [Window] icon from [iconPath].
  ///
  /// - If [small] is true, sets a 16x16 icon.
  /// - If [big] is true, sets a 48x48 or 32x32 icon.
  /// - If [cached] is true will load the icons using [loadIconCached], otherwise will call [loadIcon].
  /// - If [force] is true will always call [sendMessage], even if the icon was already set to the same icon handler.
  void setIcon(String iconPath,
      {bool small = true,
      bool big = true,
      bool cached = true,
      bool force = false}) {
    var loader = cached ? loadIconCached : loadIcon;

    if (small) {
      var hIcon = loader(iconPath, 16, 16);
      if (hIcon == 0) {
        hIcon = loader(iconPath, 32, 32);
      }

      if (force || _iconSmall != hIcon) {
        sendMessage(WM_SETICON, ICON_SMALL2, hIcon);
        _iconSmall = hIcon;
      }
    }

    if (big) {
      var hIcon = loader(iconPath, 48, 48);
      if (hIcon == 0) {
        hIcon = loader(iconPath, 32, 32);
      }

      if (force || _iconBig != hIcon) {
        sendMessage(WM_SETICON, ICON_BIG, hIcon);
        _iconBig = hIcon;
      }
    }
  }

  final Map<String, int> _iconsCache = {};

  int loadIconCached(String iconPath, int width, int height) {
    var cacheKey = '$iconPath @> $width;$height';
    return _iconsCache[cacheKey] ??= loadIcon(iconPath, width, height);
  }

  /// Loads an icon with dimensions [width] and [height] from [iconPath].
  int loadIcon(String iconPath, int width, int height) {
    var iconPathPtr = iconPath.toNativeUtf16();
    var hIcon = LoadImage(
        NULL, iconPathPtr, IMAGE_ICON, width, height, LR_LOADFROMFILE);
    return hIcon;
  }

  /// Processes a [WM_COMMAND] message. Also calls [processCommand] for [children] [Window]s.
  void processCommand(int hwnd, int hdc, int lParam) {
    for (var child in _children) {
      if (child._hwnd == lParam) {
        child.processCommand(hwnd, hdc, lParam);
      }
    }
  }

  /// Processes a [WM_CLOSE] message or a [close] call.
  /// - If returns `null` (not processed), will delegate to the default behavior of [DefWindowProc] (call [DestroyWindow]).
  /// - If returns `true` tells to close the window (minimize).
  /// - If returns `false` tells to abort the window closing (do nothing).
  bool? processClose() => true;

  /// Processes a [WM_DESTROY] message.
  void processDestroy() {}

  /// Processes a message.
  /// - Called by [WindowClass.windowProcDefault] when the messages doesn't have a default processor.
  /// - Should return a value if this messages was processed, or `null` to send to [DefWindowProc].
  int? processMessage(int hwnd, int uMsg, int wParam, int lParam) => null;

  final StreamController<Window> _onClose = StreamController();

  /// On close event (after [WM_CLOSE] message).
  /// - Called by [WindowClass.windowProcDefault].
  Stream<Window> get onClose => _onClose.stream;

  void _notifyClose() {
    _onClose.add(this);
  }

  final StreamController<Window> _onDestroyed = StreamController();

  /// On destroy event (after [WM_DESTROY] -> [WM_NCDESTROY] messages).
  /// - Called by [WindowClass.windowProcDefault].
  Stream<Window> get onDestroyed => _onDestroyed.stream;

  bool _destroyed = false;

  /// Returns `true` if the window was [destroy]ed and the `WM_NCDESTROY` was processed.
  /// - See [onDestroyed].
  bool get isDestroyed => _destroyed;

  void _notifyDestroyed() {
    _destroyed = true;

    _onDestroyed.add(this);

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

  ChildWindow({
    int? id,
    required super.windowClass,
    super.windowName,
    super.windowStyles = 0,
    super.x,
    super.y,
    super.width,
    super.height,
    super.bgColor,
    required super.defaultRepaint,
    required super.parent,
  }) : super(hMenu: id ?? newID());
}
