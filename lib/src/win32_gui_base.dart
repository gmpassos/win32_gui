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

final hInstance = HINSTANCE(GetModuleHandle(null).value);

/// A [WNDPROC] function.
/// - It's passed to a [RegisterClass] call.
/// - Uses the native callback signature (required by [Pointer.fromFunction]):
///   wrap [hwnd] with [HWND] to use it.
typedef WindowProcFunction =
    int Function(Pointer hwnd, int uMsg, int wParam, int lParam);

/// Defines the colors of a [Window].
class WindowClassColors {
  /// The text color.
  final int? textColor;

  /// The background color.
  final int? bgColor;

  WindowClassColors({this.textColor, this.bgColor});

  /// Applies the [textColor] and [bgColor] to [hdc].
  void applyColors(HDC hdc) {
    var textColor = this.textColor;
    if (textColor != null) {
      SetTextColor(hdc, COLORREF(textColor));
    }

    var bgColor = this.bgColor;
    if (bgColor != null) {
      SetBkMode(hdc, OPAQUE);
      SetBkColor(hdc, COLORREF(bgColor));
    }
  }

  int get _brushColor => bgColor ?? textColor ?? RGB(255, 255, 255);

  /// Creates a solid brush from this [WindowClassColors].
  /// - Calls Win32 [CreateSolidBrush].
  /// - The caller owns the returned brush (release it with [DeleteObject]).
  /// - See [brush] for a cached brush.
  HBRUSH createSolidBrush(HDC hdc) {
    applyColors(hdc);
    return CreateSolidBrush(COLORREF(_brushColor));
  }

  HBRUSH? _brush;

  /// Applies the colors to [hdc] and returns a cached brush
  /// (created once per instance).
  /// - Used to respond `WM_CTLCOLOR*` messages, which are sent on every
  ///   control repaint: creating a brush per message leaks GDI objects.
  /// - See [dispose].
  HBRUSH brush(HDC hdc) {
    applyColors(hdc);
    return _brush ??= CreateSolidBrush(COLORREF(_brushColor));
  }

  /// Releases the cached [brush] (if created).
  void dispose() {
    final brush = _brush;
    if (brush != null) {
      DeleteObject(HGDIOBJ(brush));
      _brush = null;
    }
  }

  @override
  String toString() {
    return 'WindowClassColors{textColor: $textColor, bgColor: $bgColor}';
  }
}

/// A [Window] class.
class WindowClass {
  /// The class name of this [Window] Class.
  final String className;

  /// The pointer to the [WNDPROC].
  /// See [WindowClass.windowProcDefault].
  final Pointer<NativeFunction<WNDPROC>> windowProc;

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
  WindowClass.custom({
    required this.className,
    required this.windowProc,
    this.isFrame = true,
    this.bgColor,
    this.useDarkMode = false,
    this.titleColor,
    this.lookupWindowGlobally = true,
  }) : custom = true;

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
    return _predefinedClasses[className] ??= WindowClass._predefined(
      className,
      bgColor,
    );
  }

  PCWSTR? _classNameNative;

  PCWSTR get classNameNative => _classNameNative ??= className.toPcwstr();

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

  /// Defines the colors for `WM_CTLCOLORDLG` message.
  static WindowClassColors? dialogColors;

  /// Handles a `WM_CTLCOLOR*` message: [wParam] is the control [HDC].
  /// - Returns the cached [WindowClassColors.brush] address,
  ///   or `0` if [colors] is `null`.
  static int createCtlColorBrush(WindowClassColors? colors, int wParam) =>
      colors?.brush(HDC(Pointer.fromAddress(wParam))).address ?? 0;

  /// A default implementation of a [windowProc] function associated with a [windowClass].
  /// - Takes the native [WNDPROC] parameters (see [WindowProcFunction]).
  static int windowProcDefault(
    Pointer hwndPtr,
    int uMsg,
    int wParamInt,
    int lParamInt,
    WindowClass windowClass,
  ) {
    final hwnd = HWND(hwndPtr);
    final wParam = WPARAM(wParamInt);
    final lParam = LPARAM(lParamInt);

    _logWindow.info(
      () =>
          'windowProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam, windowClass: ${windowClass.className}',
    );

    // An exception can't cross the native callback boundary
    // (it would be silently converted to `0`): log it.
    try {
      return _windowProcImpl(hwnd, uMsg, wParam, lParam, windowClass);
    } catch (e, s) {
      _logWindow.severe(
        'Error processing message: $uMsg (${Win32Constants.wmByID[uMsg]}) ; hwnd: $hwnd',
        e,
        s,
      );
      return uMsg == WM_CREATE ? -1 : 0;
    }
  }

  static int _ctlColor(
    WindowClassColors? colors,
    HWND hwnd,
    int uMsg,
    WPARAM wParam,
    LPARAM lParam,
  ) {
    final brush = createCtlColorBrush(colors, wParam);
    // No colors defined: default behavior.
    return brush != 0 ? brush : DefWindowProc(hwnd, uMsg, wParam, lParam);
  }

  static int _windowProcImpl(
    HWND hwnd,
    int uMsg,
    WPARAM wParam,
    LPARAM lParam,
    WindowClass windowClass,
  ) {
    var result = 0;

    final windowGlobal = windowClass.lookupWindowGlobally;
    Window? window;

    switch (uMsg) {
      case WM_CREATE:
        {
          // Lookup `Window` by `_createId` first (an `HWND` can be reused):
          if (lParam != 0) {
            window = windowClass.getWindowWithCreateIdPtr(
              hwnd,
              lParam,
              nullHwnd: true,
              ptrIsCreateStruct: true,
            );

            window?._hwnd = hwnd;
          }

          window ??= windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);

          _logWindow.info(() => "WM_CREATE> hwnd: $hwnd ; window: $window");

          // Window found, build it:
          if (window != null) {
            if (windowClass.useDarkMode) {
              window.setupDarkMode();
            }

            window.setupTitleColor(windowClass.titleColor);

            final hdc = GetDC(hwnd);
            try {
              window.callBuild(hdc: hdc);
            } finally {
              ReleaseDC(hwnd, hdc);
            }

            result = 0;
          }
          // Missing window, destroy it:
          else {
            result = -1;
          }
        }
      case WM_PAINT:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null && !window.defaultRepaint) {
            final ps = calloc<PAINTSTRUCT>();
            final hdc = BeginPaint(hwnd, ps);

            try {
              window.callRepaint(hdc: hdc);
            } finally {
              // Always validate the region (otherwise `WM_PAINT` loops):
              EndPaint(hwnd, ps);
              free(ps);
            }

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
            try {
              window.processCommand(hwnd, hdc, wParam, lParam);
            } finally {
              ReleaseDC(hwnd, hdc);
            }
          }
        }
      case WM_CTLCOLORSTATIC:
        {
          result = _ctlColor(staticColors, hwnd, uMsg, wParam, lParam);
        }
      case WM_CTLCOLORBTN:
        {
          result = _ctlColor(buttonColors, hwnd, uMsg, wParam, lParam);
        }
      case WM_CTLCOLORLISTBOX:
        {
          result = _ctlColor(listBoxColors, hwnd, uMsg, wParam, lParam);
        }
      case WM_CTLCOLOREDIT:
        {
          result = _ctlColor(editColors, hwnd, uMsg, wParam, lParam);
        }
      case WM_CTLCOLORSCROLLBAR:
        {
          result = _ctlColor(scrollBarColors, hwnd, uMsg, wParam, lParam);
        }
      case WM_CTLCOLORDLG:
        {
          result = _ctlColor(dialogColors, hwnd, uMsg, wParam, lParam);
        }

      case WM_CLOSE:
        {
          window = windowClass.getWindowWithHWnd(hwnd, global: windowGlobal);
          if (window != null) {
            var shouldClose = window.processClose();
            window.notifyClose();

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
          window?.notifyDestroyed();
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

  /// Lookup a [Window] by `createID` in [CREATESTRUCT] pointer;
  Window? getWindowWithCreateIdPtr(
    HWND hwnd,
    int createIdPtrAddress, {
    required bool nullHwnd,
    required bool ptrIsCreateStruct,
  }) {
    Pointer<Uint32> createIdPtr;
    String? windowName;

    if (ptrIsCreateStruct) {
      var createStructPtr = Pointer<CREATESTRUCT>.fromAddress(
        createIdPtrAddress,
      );
      var createStruct = createStructPtr.ref;

      // `lpszName` is `NULL` for a window without a name:
      final lpszName = createStruct.lpszName;
      windowName = lpszName.isNull ? null : lpszName.toDartString();

      // Created without a `createId` (e.g. by external code):
      if (createStruct.lpCreateParams.isNull) return null;

      try {
        createIdPtr = createStruct.lpCreateParams.cast<Uint32>();
      } catch (e, s) {
        _logWindow.severe(
          "Error resolving `createId` pointer from `CREATESTRUCT` to hWnd: $hwnd",
          e,
          s,
        );
        return null;
      }
    } else {
      try {
        createIdPtr = Pointer<Uint32>.fromAddress(createIdPtrAddress);
      } catch (e, s) {
        _logWindow.severe(
          "Error resolving `createId` pointer to hWnd: $hwnd",
          e,
          s,
        );
        return null;
      }
    }

    var createId = createIdPtr.value;

    return getWindowWithCreateId(
      createId,
      hwnd: nullHwnd ? null : hwnd,
      windowName: windowName,
    );
  }

  /// Lookup a [Window] by `_createID`;
  Window? getWindowWithCreateId(
    int createId, {
    HWND? hwnd,
    String? windowName,
  }) {
    if (createId > 0 && createId <= Window._createIdCount) {
      return _windows.firstWhereOrNull(
        (w) =>
            w._createId == createId &&
            w._hwnd == hwnd &&
            (windowName == null || w.windowName == windowName),
      );
    }

    return null;
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
  Window? getWindowWithHWnd(HWND hwnd, {bool global = false}) {
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
      ..lpszClassName = PWSTR(windowClass.classNameNative)
      ..lpfnWndProc = windowClass.windowProc
      ..style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC
      ..hCursor = LoadCursor(null, IDC_ARROW).value;

    if (windowClass.isFrame) {
      wcRef.hIcon = LoadIcon(null, IDI_APPLICATION).value;
    }

    HBRUSH? hbrBackground;

    final bgColor = windowClass.bgColor;
    if (bgColor != null) {
      wcRef.hbrBackground = hbrBackground = CreateSolidBrush(COLORREF(bgColor));
    }

    final r = RegisterClass(wc);

    // `RegisterClass` copies the `WNDCLASS`:
    free(wc);

    final id = r.value;

    // Failed (e.g. `ERROR_CLASS_ALREADY_EXISTS`):
    if (id == 0) {
      if (hbrBackground != null) {
        DeleteObject(HGDIOBJ(hbrBackground));
      }

      _logWindow.severe(
        "Can't register `WindowClass`: ${windowClass.className} ; errorCode: ${r.error}",
      );
      return false;
    }

    _registeredWindowClasses[windowClass.className] = id;

    return true;
  }

  @override
  String toString() {
    return 'WindowClass{className: $className, bgColor: $bgColor, useDarkMode: $useDarkMode, titleColor: $titleColor, windows: ${_windows.length}}';
  }
}

/// The [Window] message loop implementation.
/// - See https://learn.microsoft.com/en-us/windows/win32/winmsg/using-messages-and-message-queues
class WindowMessageLoop {
  /// Runs a [Window] message consumer loop that blocks the current thread/`Isolate`.
  ///
  /// - If [condition] is passed loops while [condition] is `true`.
  /// - Uses Win32 [GetMessage] to consume the [Window] messages (blocking call).
  /// - See [runLoopAsync].
  static void runLoop({bool Function()? condition}) {
    condition ??= () => true;

    final msg = calloc<MSG>();

    while (condition() && GetMessage(msg, null, 0, 0).value) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }

    free(msg);
  }

  static const yieldMS1 = Duration(milliseconds: 1);
  static const yieldMS10 = Duration(milliseconds: 10);
  static const yieldMS30 = Duration(milliseconds: 30);

  /// Runs a [Window] message consumer loop capable to [timeout] and also
  /// allows Dart [Future]s to be processed while processing messages.
  ///
  /// - If [condition] is passed loops while [condition] is `true`.
  /// - Uses Win32 [PeekMessage] to consume the [Window] messages (non-blocking call).
  /// - See [runLoop].
  static Future<int> runLoopAsync({
    Duration? timeout,
    int maxConsecutiveDispatches = 100,
    bool Function()? condition,
  }) async {
    maxConsecutiveDispatches = maxConsecutiveDispatches.clamp(2, 1000);
    condition ??= () => true;

    final initTime = DateTime.now();

    final msg = calloc<MSG>();

    var totalMsgCount = 0;
    var noMsgCount = 0;
    var msgCount = 0;

    while (condition()) {
      var got = PeekMessage(msg, null, 0, 0, PM_REMOVE);

      if (!got) {
        got = PeekMessage(msg, null, 0, 0, PM_REMOVE);
      }

      if (got) {
        // `PostQuitMessage` (see `Window.quit`): stop the loop.
        if (msg.ref.message == WM_QUIT) break;

        totalMsgCount++;
        noMsgCount = 0;
        ++msgCount;

        TranslateMessage(msg);
        DispatchMessage(msg);

        if ((msgCount % maxConsecutiveDispatches) == 0 && msgCount > 0) {
          if (initTime.timeOut(timeout)) break;

          await Future.delayed(yieldMS1);
        }
      } else {
        ++noMsgCount;
        msgCount = 0;

        if (noMsgCount > 1) {
          if (initTime.timeOut(timeout)) break;

          var yieldMS = switch (noMsgCount) {
            > 300 => yieldMS30,
            > 100 => yieldMS10,
            _ => yieldMS1,
          };

          await Future.delayed(yieldMS);
        }
      }
    }

    free(msg);

    return totalMsgCount;
  }

  /// Consumes the message queue.
  /// - Returns the amount of processed messages.
  /// - Calls Win32 [PeekMessage] (removing from que queue).
  /// - Stops after consume reaches [maxMessages] or when the queue is empty.
  static int consumeQueue({int maxMessages = 3}) {
    final msg = calloc<MSG>();

    var totalMsgCount = 0;
    var noMessageCount = 0;

    while (totalMsgCount < maxMessages) {
      var got = PeekMessage(msg, null, 0, 0, PM_REMOVE);

      if (!got) {
        got = PeekMessage(msg, null, 0, 0, PM_REMOVE);
      }

      if (got) {
        // Don't swallow a `WM_QUIT`: re-post it for the main message loop.
        if (msg.ref.message == WM_QUIT) {
          PostQuitMessage(msg.ref.wParam);
          break;
        }

        totalMsgCount++;

        TranslateMessage(msg);
        DispatchMessage(msg);
      } else {
        ++noMessageCount;

        if (noMessageCount >= 2) {
          break;
        }
      }
    }

    free(msg);

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

/// A base class for [Window] or [Dialog].
abstract class WindowBase<W extends WindowBase<W>> implements Finalizable {
  /// The [x] coordinate of this [Window] when created.
  int? x;

  /// The [y] coordinate of this [Window] when created.
  int? y;

  /// The [width] of this [Window] when created.
  int? width;

  /// The [height] of this [Window] when created.
  int? height;

  /// Returns `true` if this [Window] was created.
  bool get created => hwndIfCreated != null;

  /// The window handler ID (if [created]).
  HWND get hwnd {
    final hwnd = hwndIfCreated;
    if (hwnd == null) {
      throw StateError(
        "Window not created! `hwnd` not defined! Method `create()` should be called before use of `hwnd`.",
      );
    }
    return hwnd;
  }

  /// Returns the window handler ID if [created] or `null`.
  HWND? get hwndIfCreated;

  WindowBase({this.x, this.y, this.width, this.height}) {
    // Release the native buffers when this instance is garbage collected
    // (not on destroy: they may still be read after it).
    attachNativeFinalizer(dimension, sizeOf<RECT>());
    attachNativeFinalizer(_rect, sizeOf<RECT>());
  }

  static final _nativeFinalizer = NativeFinalizer(calloc.nativeFree);

  /// Attaches a [NativeFinalizer] to this instance that releases [pointer]
  /// (allocated with [calloc]) when this instance is garbage collected.
  void attachNativeFinalizer(Pointer pointer, int size) =>
      _nativeFinalizer.attach(this, pointer.cast(), externalSize: size);

  /// The `create` ID.
  ///
  /// Used to identify this class instance while
  /// responding to a [WM_CREATE] or [WM_INITDIALOG] message.
  int get createId;

  /// Creates the [Window] or [Dialog].
  /// - Should call: `await` [ensureLoaded].
  Future<HWND> create();

  Future<void>? _loadCall;

  /// Ensures that [load] was called.
  Future<void> ensureLoaded() => _loadCall ??= _callLoad();

  Future<void> _callLoad() async {
    await load();
  }

  /// Loads asynchronous resources.
  /// - Do not call directly, use [ensureLoaded].
  /// - Note that Win32 API [build] and [repaint] won't allow any asynchronous call ([Future]s).
  Future<void> load() async {}

  /// Setup a dark mode.
  /// - Calls Win32 [DwmSetWindowAttribute] [DWMWA_USE_IMMERSIVE_DARK_MODE].
  void setupDarkMode() {
    // Win32 `BOOL` (32-bit):
    var value = malloc<Int32>()..value = TRUE;

    try {
      DwmSetWindowAttribute(
        hwnd,
        DWMWA_USE_IMMERSIVE_DARK_MODE,
        value,
        sizeOf<Int32>(),
      );
    } on WindowsException catch (e) {
      _logWindow.warning("Can't setup dark mode: $e");
    } finally {
      free(value);
    }
  }

  /// Setup the title color.
  /// - Calls Win32 [DwmSetWindowAttribute] [DWMWA_CAPTION_COLOR].
  void setupTitleColor(int? titleColor) {
    if (titleColor == null) return;

    // Win32 `COLORREF` (32-bit):
    var value = malloc<Uint32>()..value = titleColor;

    try {
      DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, value, sizeOf<Uint32>());
    } on WindowsException catch (e) {
      _logWindow.warning("Can't setup title color: $e");
    } finally {
      free(value);
    }
  }

  /// Calls [build] resolving necessary parameters.
  /// - Used by [WindowClass.windowProcDefault] or [Dialog.dialogProcDefault].
  bool callBuild({HDC? hdc}) {
    ensureLoaded();
    final hwnd = this.hwnd;

    _logWindow.info(() => "Building> $this");

    if (hdc == null) {
      final hdc = GetDC(hwnd);
      _callBuildImpl(hwnd, hdc);
      ReleaseDC(hwnd, hdc);
    } else {
      _callBuildImpl(hwnd, hdc);
    }

    return true;
  }

  void _callBuildImpl(HWND hwnd, HDC hdc) {
    fetchDimension();
    build(hwnd, hdc);
  }

  /// [Window] build procedure.
  void build(HWND hwnd, HDC hdc) {
    SetMapMode(hdc, MM_ISOTROPIC);
    SetViewportExtEx(hdc, 1, 1, nullptr);
    SetWindowExtEx(hdc, 1, 1, nullptr);
  }

  /// Sends a [message] to this [Window].
  int sendMessage(int message, int wParam, int lParam) {
    final hwnd = this.hwnd;
    return SendMessage(hwnd, message, WPARAM(wParam), LPARAM(lParam)).value;
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
  bool updateWindow() => UpdateWindow(hwnd);

  final _rect = calloc<RECT>();

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
    return RedrawWindow(hwnd, r, null, REDRAW_WINDOW_FLAGS(flags));
  }

  /// Invalidates [Window] region.
  /// - Calls Win32 [InvalidateRect].
  bool invalidateRect({
    math.Rectangle? rect,
    Pointer<RECT>? pRect,
    bool eraseBg = true,
  }) {
    var r = _resolveRect(rect, pRect);
    return InvalidateRect(hwnd, r, eraseBg);
  }

  /// Request a [WM_PAINT] event of the entire [Window] client area.
  /// - Calls [invalidateRect] without any parameter.
  bool requestRepaint() => invalidateRect();

  /// Sets this [Window] rounded corners attributes.
  /// - If [rounded] is `true` will set this [Window] with rounded corners,
  ///   otherwise will disable the rounded corners.
  /// - If [small] is `true` round the corners with a small radius.
  void setWindowRoundedCorners({bool rounded = true, bool small = false}) {
    final pref = calloc<DWORD>();
    try {
      final hwnd = this.hwnd;

      pref.value = rounded
          ? (small ? DWMWCP_ROUNDSMALL : DWMWCP_ROUND)
          : DWMWCP_DONOTROUND;

      DwmSetWindowAttribute(
        hwnd,
        DWMWA_WINDOW_CORNER_PREFERENCE,
        pref,
        sizeOf<DWORD>(),
      );
    } on WindowsException catch (e) {
      // Not supported before Windows 11:
      _logWindow.warning("Can't set window rounded corners: $e");
    } finally {
      free(pref);
    }
  }

  HICON? _iconSmall;
  HICON? _iconBig;

  /// Sets this [Window] icon from [iconPath].
  ///
  /// - If [small] is true, sets a 16x16 icon.
  /// - If [big] is true, sets a 48x48 or 32x32 icon.
  /// - If [cached] is true will load the icons using [loadIconCached], otherwise will call [loadIcon].
  /// - If [force] is true will always call [sendMessage], even if the icon was already set to the same icon handler.
  void setIcon(
    String iconPath, {
    bool small = true,
    bool big = true,
    bool cached = true,
    bool force = false,
  }) {
    var loader = cached ? Window.loadIconCached : Window.loadIcon;

    if (small) {
      var hIcon = loader(iconPath, 16, 16);
      if (hIcon.isNull) {
        hIcon = loader(iconPath, 32, 32);
      }

      if (force || _iconSmall != hIcon) {
        // `WM_SETICON` accepts `ICON_SMALL`/`ICON_BIG`
        // (`ICON_SMALL2` is only valid for `WM_GETICON`):
        sendMessage(WM_SETICON, ICON_SMALL, hIcon.address);
        _iconSmall = hIcon;
      }
    }

    if (big) {
      var hIcon = loader(iconPath, 48, 48);
      if (hIcon.isNull) {
        hIcon = loader(iconPath, 32, 32);
      }

      if (force || _iconBig != hIcon) {
        sendMessage(WM_SETICON, ICON_BIG, hIcon.address);
        _iconBig = hIcon;
      }
    }
  }

  /// Shows this [Window].
  /// - Calls Win32 [ShowWindow] [SW_SHOWNORMAL].
  void show() {
    final hwnd = this.hwnd;

    ShowWindow(hwnd, SW_SHOWNORMAL);
  }

  // Note: Win32 `ShowWindow` returns the previous visibility state
  // (not success), so the methods below return the resulting state.

  /// Minimizes this [Window].
  /// - Calls Win32 [ShowWindow] [SW_MINIMIZE].
  /// - Returns [isMinimized].
  bool minimize() {
    ShowWindow(hwnd, SW_MINIMIZE);
    return isMinimized;
  }

  /// Maximized this [Window].
  /// - Calls Win32 [ShowWindow] [SW_MAXIMIZE].
  /// - Returns [isMaximized].
  bool maximize() {
    ShowWindow(hwnd, SW_MAXIMIZE);
    return isMaximized;
  }

  /// Restores this [Window].
  /// - Calls Win32 [ShowWindow] [SW_RESTORE].
  /// - Returns `true` if it's not minimized or maximized after the call.
  bool restore() {
    ShowWindow(hwnd, SW_RESTORE);
    return !isMinimized && !isMaximized;
  }

  /// Returns if this [Window] is minimized.
  /// - See [getWindowLongPtr].
  bool get isMinimized => (getWindowLongPtr(GWL_STYLE) & WS_MINIMIZE) != 0;

  /// Returns if this [Window] is maximized.
  /// - See [getWindowLongPtr].
  bool get isMaximized => (getWindowLongPtr(GWL_STYLE) & WS_MAXIMIZE) != 0;

  int getWindowLongPtr(int nIndex) {
    final hwnd = this.hwnd;
    return GetWindowLongPtr(hwnd, WINDOW_LONG_PTR_INDEX(nIndex)).value;
  }

  /// Closes this [Window].
  /// - Returns `true` (closed) and calls [destroy] if `processClose` returns `null`
  ///   (the default `WM_CLOSE` behavior: [DestroyWindow]).
  ///   Note: Win32 [CloseWindow] minimizes a window, it doesn't close it.
  /// - Returns `false` (minimize) if `processClose` returns `true` (confirm close).
  /// - Returns `null` (do nothing) if `processClose` returns `false` (abort close).
  bool? close() {
    var shouldClose = processClose();
    notifyClose();

    if (shouldClose == null) {
      return destroy();
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
  bool destroy() {
    final hwnd = this.hwnd;

    var r = DestroyWindow(hwnd);
    // retry:
    if (!r.value) {
      WindowMessageLoop.consumeQueue();
      r = DestroyWindow(hwnd);
    }

    if (!r.value) {
      _logWindow.warning(
        "Error destroying `Window`> errorCode: ${r.error} ; hwnd: $hwnd -> $this",
      );
      return false;
    }

    return true;
  }

  /// Shows a message dialog.
  /// - Calls Win32 [MessageBox].
  /// - See [showDialog].
  int showMessage(
    String title,
    String text, {
    int flags = 0,
    bool iconWarning = false,
    bool iconInformation = true,
    bool modal = false,
  }) {
    if (iconWarning) {
      flags |= MB_ICONWARNING;
    } else if (iconInformation) {
      flags |= MB_ICONINFORMATION;
    }

    return showDialog(title, text, flags: flags, modal: modal);
  }

  /// Shows a confirmation dialog.
  /// - Calls Win32 [MessageBox].
  /// - See [showDialog].
  bool showConfirmationDialog(
    String title,
    String text, {
    int flags = MB_ICONQUESTION,
    bool okCancel = false,
    bool yesNo = true,
    bool cancel = false,
    bool modal = false,
  }) {
    if (okCancel) {
      flags |= MB_OKCANCEL;
    } else if (yesNo) {
      flags |= cancel ? MB_YESNOCANCEL : MB_YESNO;
    }

    final r = showDialog(title, text, flags: flags, modal: modal);
    return r == IDYES || r == IDOK;
  }

  /// Shows a dialog.
  /// - Calls Win32 [MessageBox].
  int showDialog(
    String title,
    String text, {
    int flags = 0,
    bool modal = false,
  }) {
    final hwnd = this.hwnd;

    final titlePointer = title.toPcwstr();
    final textPointer = text.toPcwstr();

    if (modal) {
      flags |= MB_SYSTEMMODAL;
    }

    final result = MessageBox(
      hwnd,
      textPointer,
      titlePointer,
      MESSAGEBOX_STYLE(flags),
    ).value;

    free(titlePointer);
    free(textPointer);

    return result;
  }

  /// Paint operation: fills a rectangle with [color].
  void fillRect(
    HDC hdc,
    int color, {
    math.Rectangle? rect,
    Pointer<RECT>? pRect,
  }) {
    var r = _resolveRect(rect, pRect);

    if (r != null) {
      final hBrush = CreateSolidBrush(COLORREF(color));
      FillRect(hdc, r, hBrush);
      DeleteObject(HGDIOBJ(hBrush));
    }
  }

  /// Returns this [Window] text length.
  /// - Calls Win32 [GetWindowTextLength].
  /// - See [getWindowText].
  int getWindowTextLength() => GetWindowTextLength(hwnd).value;

  /// Returns this [Window] text.
  /// - Calls Win32 [getWindowTextLength] and [GetWindowText].
  /// - See [getWindowTextLength].
  String getWindowText({int? length}) {
    length ??= getWindowTextLength();
    final strPtr = wsalloc(length + 1);
    GetWindowText(hwnd, strPtr, length + 1);
    final str = strPtr.toDartString();
    free(strPtr);
    return str;
  }

  /// Sets this [Window] text.
  /// - Calls Win32 [SetWindowText].
  /// - See [getWindowText].
  bool setWindowText(String text) {
    final textPtr = text.toPcwstr();
    final ok = SetWindowText(hwnd, textPtr).value;
    free(textPtr);
    return ok;
  }

  /// Paint operation: draws [text] at coordinates [x], [y].
  void drawText(HDC hdc, String text, int x, int y) {
    final s = text.toPcwstr();
    TextOut(hdc, x, y, s, text.length);
    free(s);
  }

  /// Paint operation: draws [hBitmap] at coordinates [x], [y].
  /// - Calls Win32 [BitBlt] to copy the Bitmap bytes to this [Window].
  void drawImage(
    HDC hdc,
    HBITMAP hBitmap,
    int x,
    int y,
    int width,
    int height,
  ) {
    final hMemDC = CreateCompatibleDC(hdc);

    SelectObject(hMemDC, HGDIOBJ(hBitmap));
    BitBlt(hdc, x, y, width, height, hMemDC, 0, 0, SRCCOPY);
    DeleteDC(hMemDC);
  }

  /// Processes a [WM_COMMAND] message.
  void processCommand(HWND hwnd, HDC hdc, int wParam, int lParam) {}

  /// Processes a [WM_CLOSE] message or a [close] call.
  /// - If returns `null` (not processed), will delegate to the default behavior of [DefWindowProc] (call [DestroyWindow]).
  /// - If returns `true` tells to close the window (minimize).
  /// - If returns `false` tells to abort the window closing (do nothing).
  bool? processClose();

  /// Processes a [WM_DESTROY] message.
  void processDestroy() {}

  /// Processes a message.
  /// - Called by [WindowClass.windowProcDefault] when the messages doesn't have a default processor.
  /// - Should return a value if this messages was processed, or `null` to send to [DefWindowProc].
  int? processMessage(HWND hwnd, int uMsg, int wParam, int lParam) => null;

  final StreamController<W> _onClose = StreamController.broadcast();

  /// On close event (after [WM_CLOSE] message).
  /// - Called by [WindowClass.windowProcDefault].
  /// - A broadcast [Stream], closed when the window is destroyed.
  Stream<W> get onClose => _onClose.stream;

  /// Should be called while processing a [WM_CLOSE] message.
  void notifyClose() {
    if (_onClose.isClosed) return;
    _onClose.add(this as W);
  }

  final StreamController<W> _onDestroyed = StreamController.broadcast();

  /// On destroy event (after [WM_DESTROY] -> [WM_NCDESTROY] messages).
  /// - Called by [WindowClass.windowProcDefault].
  /// - A broadcast [Stream], closed after the destroy event.
  Stream<W> get onDestroyed => _onDestroyed.stream;

  bool _destroyed = false;

  /// Returns `true` if the window was [destroy]ed and the `WM_NCDESTROY` was processed.
  /// - See [onDestroyed].
  bool get isDestroyed => _destroyed;

  /// Should be called while processing a [WM_NCDESTROY] message.
  void notifyDestroyed() {
    if (_destroyed) return;
    _destroyed = true;

    _onDestroyed.add(this as W);

    var waitingDestroyed = _waitingDestroyed;
    if (waitingDestroyed != null && !waitingDestroyed.isCompleted) {
      waitingDestroyed.complete(true);
      _waitingDestroyed = null;
    }

    doDestroy();

    _onClose.close();
    _onDestroyed.close();
  }

  /// Perform final destroy operations for this instance.
  void doDestroy();

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
}

/// A Win32 Window.
/// - See [ChildWindow].
/// - See https://learn.microsoft.com/en-us/windows/win32/learnwin32/what-is-a-window-
class Window extends WindowBase<Window> {
  /// Alias to [WindowMessageLoop.runLoop].
  static void runMessageLoop({bool Function()? condition}) =>
      WindowMessageLoop.runLoop(condition: condition);

  /// Alias to [WindowMessageLoop.runLoopAsync].
  static Future<int> runMessageLoopAsync({
    Duration? timeout,
    int maxConsecutiveDispatches = 100,
    bool Function()? condition,
  }) => WindowMessageLoop.runLoopAsync(
    timeout: timeout,
    maxConsecutiveDispatches: maxConsecutiveDispatches,
    condition: condition,
  );

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

    var r = SystemParametersInfo(
      SPI_GETNONCLIENTMETRICS,
      ncmSz,
      ncm,
      SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
    );

    if (!r.value) {
      free(ncm);
      throw StateError(
        "Can't call `SystemParametersInfo(SPI_GETNONCLIENTMETRICS...)`. Error: ${r.error}",
      );
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

  /// The background color of this [Window] (if applicable).
  int? bgColor;

  /// The [hMenu] parameter passed to [CreateWindowEx].
  /// - If this is a [ChildWindow] this is the child element ID ([ChildWindow.id]).
  final int? hMenu;

  /// The parent [Window] of this instance.
  /// - See [ChildWindow].
  final Window? parent;

  /// If `true` will perform a default repaint and
  /// will NOT call the custom [repaint] method.
  bool defaultRepaint;

  Window({
    required this.windowClass,
    this.windowName,
    this.windowStyles = 0,
    super.x,
    super.y,
    super.width,
    super.height,
    this.bgColor,
    this.hMenu,
    required this.defaultRepaint,
    this.parent,
  }) {
    windowClass.register();
    windowClass.registerWindow(this);

    parent?._addChild(this);
  }

  PCWSTR? _windowNameNative;

  /// The [windowName] as a native string, or `null` if [windowName] is `null`.
  PCWSTR? get windowNameNative {
    final windowName = this.windowName;
    if (windowName == null) return null;

    var windowNameNative = _windowNameNative;
    if (windowNameNative == null) {
      _windowNameNative = windowNameNative = windowName.toPcwstr(
        allocator: calloc,
      );
      attachNativeFinalizer(windowNameNative, (windowName.length + 1) * 2);
    }

    return windowNameNative;
  }

  static int _createIdCount = 0;

  final int _createId = ++_createIdCount;

  @override
  int get createId => _createId;

  HWND? _hwnd;

  @override
  HWND? get hwndIfCreated => _hwnd;

  /// Creates this [Window].
  @override
  Future<HWND> create({bool createChildren = true}) async {
    await ensureLoaded();

    final createIdPtr = calloc<Uint32>();
    createIdPtr.value = _createId;

    final Win32Result<HWND> r;
    try {
      r = createWindowImpl(createIdPtr);
    } finally {
      // `WM_CREATE` (which reads `createIdPtr`) is processed synchronously:
      free(createIdPtr);
    }

    final hwnd = r.value;

    if (hwnd.isNull) {
      throw StateError("Can't create window> errorCode: ${r.error} -> $this");
    }

    if (_hwnd != null && _hwnd != hwnd) {
      throw StateError(
        "`WM_CREATE` `Window` lookup error: _hwnd:$_hwnd != hwnd:$hwnd",
      );
    }

    _hwnd = hwnd;

    _logWindow.info(() => "Created Window #$hwnd: $this");

    if (createChildren) {
      for (var c in _children) {
        await c.create();
      }
    }

    return hwnd;
  }

  /// Window creation implementation.
  /// - Calls Win32 [CreateWindowEx] by default.
  /// - Allows @[override].
  Win32Result<HWND> createWindowImpl(Pointer<Uint32> createIdPtr) {
    final hMenu = this.hMenu;

    return CreateWindowEx(
      // Optional window styles:
      WINDOW_EX_STYLE(0),

      // Window class:
      windowClass.classNameNative,

      // Window text:
      windowNameNative,

      // Window style:
      WINDOW_STYLE(windowStyles),

      // Size and position:
      x ?? CW_USEDEFAULT,
      y ?? CW_USEDEFAULT,
      width ?? CW_USEDEFAULT,
      height ?? CW_USEDEFAULT,

      // Parent window:
      parent?._hwnd,
      // Menu (or child ID):
      hMenu != null ? HMENU(Pointer.fromAddress(hMenu)) : null,
      // Instance handle:
      hInstance,
      // Pass the `_createId`
      createIdPtr,
    );
  }

  final List<Window> _children = [];

  List<Window> get children => UnmodifiableListView(_children);

  void _addChild(Window child) {
    if (_children.contains(child)) {
      throw StateError("Child already added: $child");
    }

    _logWindow.info(
      () =>
          'Add child> #$hwndIfCreated<${windowClass.className}>[${windowName ?? ''}] -> ${child.hwndIfCreated}<${child.windowClass.className}>[${child.windowName ?? ''}]',
    );

    _children.add(child);
  }

  @override
  Future<void> _callLoad() async {
    await load();

    for (var child in _children) {
      await child.ensureLoaded();
    }
  }

  /// Calls [repaint] resolving necessary parameters.
  /// - Used by [WindowClass.windowProcDefault] (with the `WM_PAINT` [hdc]).
  /// - If [hdc] is `null` (a call outside `WM_PAINT`) uses [GetDC].
  ///   Note: [BeginPaint] is only valid while processing `WM_PAINT`.
  bool callRepaint({HDC? hdc}) {
    ensureLoaded();

    final hwnd = this.hwnd;

    if (defaultRepaint) {
      return false;
    }

    if (hdc == null) {
      final hdc = GetDC(hwnd);
      try {
        _callRepaintImpl(hwnd, hdc);
      } finally {
        ReleaseDC(hwnd, hdc);
      }
    } else {
      _callRepaintImpl(hwnd, hdc);
    }

    return true;
  }

  void _callRepaintImpl(HWND hwnd, HDC hdc) {
    fetchDimension();
    repaint(hwnd, hdc);
  }

  /// [Window] custom repaint procedure.
  /// - [defaultRepaint] should be `false` to call a custom [repaint].
  void repaint(HWND hwnd, HDC hdc) {}

  /// Sends quit message with [exitCode].
  /// - Calls Win32 [PostQuitMessage].
  static void quit([int exitCode = 0]) {
    PostQuitMessage(exitCode);
  }

  /// Paint operation: draws this [Window] background.
  void drawBG(HDC hdc, {int? bgColor}) {
    bgColor ??= this.bgColor;

    if (bgColor != null) {
      fillRect(hdc, bgColor, pRect: dimension);
    }
  }

  static final Map<String, HBITMAP> _imagesCached = {};

  /// Cached version of [loadImage].
  /// -- See [getBitmapDimension].
  static HBITMAP loadImageCached(
    String imgPath, {
    int imgWidth = 0,
    int imgHeight = 0,
  }) => _imagesCached[imgPath] ??= loadImage(
    imgPath,
    imgWidth: imgWidth,
    imgHeight: imgHeight,
  );

  /// Loads image from [imgPath] with dimension [imgWidth], [imgHeight].
  /// - The image should be a 24bit Bitmap.
  /// - See [loadImageCached] and [getBitmapDimension].
  static HBITMAP loadImage(
    String imgPath, {
    int imgWidth = 0,
    int imgHeight = 0,
  }) {
    var imgPathPtr = imgPath.toPcwstr();
    final hBitmap = LoadImage(
      null,
      imgPathPtr,
      IMAGE_BITMAP,
      imgWidth,
      imgHeight,
      LR_LOADFROMFILE,
    ).value;
    free(imgPathPtr);
    return HBITMAP(hBitmap);
  }

  /// Returns the [hBitmap] dimension.
  /// - Calls [GetObject].
  static ({int width, int height})? getBitmapDimension(HBITMAP hBitmap) {
    var bm = calloc<BITMAP>();

    var ok = GetObject(HGDIOBJ(hBitmap), sizeOf<BITMAP>(), bm) != 0;
    if (!ok) {
      free(bm);
      return null;
    }

    var dimension = (width: bm.ref.bmWidth, height: bm.ref.bmHeight);
    free(bm);

    return dimension;
  }

  static final Map<String, HICON> _iconsCache = {};

  static HICON loadIconCached(String iconPath, int width, int height) {
    var cacheKey = '$iconPath @> $width;$height';
    return _iconsCache[cacheKey] ??= loadIcon(iconPath, width, height);
  }

  /// Loads an icon with dimensions [width] and [height] from [iconPath].
  static HICON loadIcon(String iconPath, int width, int height) {
    var iconPathPtr = iconPath.toPcwstr();
    var hIcon = LoadImage(
      null,
      iconPathPtr,
      IMAGE_ICON,
      width,
      height,
      LR_LOADFROMFILE,
    ).value;
    free(iconPathPtr);
    return HICON(hIcon);
  }

  /// Processes a [WM_COMMAND] message. Also calls [processCommand] for [children] [Window]s.
  @override
  void processCommand(HWND hwnd, HDC hdc, int wParam, int lParam) {
    for (var child in _children) {
      // For a control notification `lParam` is the control `HWND`:
      if (child._hwnd?.address == lParam) {
        child.processCommand(hwnd, hdc, wParam, lParam);
      }
    }
  }

  @override
  bool? processClose() => true;

  @override
  void doDestroy() {
    windowClass.unregisterWindow(this);

    // Child windows are destroyed with their parent, but children of a
    // predefined class (e.g. `Button`, `RichEdit`) don't receive
    // `WM_NCDESTROY` in `windowProcDefault`: notify them here
    // (otherwise they stay registered with a stale `HWND`).
    for (var child in _children) {
      child.notifyDestroyed();
    }
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
