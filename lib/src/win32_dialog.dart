import 'dart:async';
import 'dart:ffi';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:win32/win32.dart';

import 'win32_constants.dart';
import 'win32_gui_base.dart';

final _logDialog = logging.Logger('Win32:Dialog');

/// A Win32 Dialog.
class Dialog<R> extends WindowBase<Dialog> {
  /// Alias to [WindowClass.staticColors].
  static WindowClassColors? get staticColors => WindowClass.staticColors;

  static set staticColors(WindowClassColors? colors) =>
      WindowClass.staticColors = colors;

  /// Alias to [WindowClass.buttonColors].
  static WindowClassColors? get buttonColors => WindowClass.buttonColors;

  static set buttonColors(WindowClassColors? colors) =>
      WindowClass.buttonColors = colors;

  /// Alias to [WindowClass.listBoxColors].
  static WindowClassColors? get listBoxColors => WindowClass.listBoxColors;

  static set listBoxColors(WindowClassColors? colors) =>
      WindowClass.listBoxColors = colors;

  /// Alias to [WindowClass.editColors].
  static WindowClassColors? get editColors => WindowClass.editColors;

  static set editColors(WindowClassColors? colors) =>
      WindowClass.editColors = colors;

  /// Alias to [WindowClass.scrollBarColors].
  static WindowClassColors? get scrollBarColors => WindowClass.scrollBarColors;

  static set scrollBarColors(WindowClassColors? colors) =>
      WindowClass.scrollBarColors = colors;

  /// Alias to [WindowClass.dialogColors].
  static WindowClassColors? get dialogColors => WindowClass.dialogColors;

  static set dialogColors(WindowClassColors? colors) =>
      WindowClass.dialogColors = colors;

  /// The default [Dialog] [DLGPROC ] implementation.
  static int dialogProcDefault(int hwnd, int uMsg, int wParam, int lParam) {
    var result = 0;

    _logDialog.info(() =>
        'Dialog.dialogProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam');

    Dialog? dialog;

    switch (uMsg) {
      case WM_INITDIALOG:
        {
          dialog = getDialogWithHWnd(hwnd);

          // Lookup `Dialog` by `_createId`:
          if (dialog == null && lParam != 0) {
            dialog = getDialogWithCreateIdPtr(hwnd, lParam, nullHwnd: true);

            dialog?._hwnd = hwnd;
          }

          _logDialog.info(() => "WM_INITDIALOG> hwnd: $hwnd ; window: $dialog");

          final hdc = GetDC(hwnd);

          if (dialog != null) {
            if (dialog.useDarkMode) {
              dialog.setupDarkMode();
            }

            dialog.setupTitleColor(dialog.titleColor);

            dialog.callBuild(hdc: hdc);
          }

          ReleaseDC(hwnd, hdc);

          result = TRUE;
        }
      case WM_COMMAND:
        {
          dialog = getDialogWithHWnd(hwnd);

          if (dialog != null) {
            final hdc = GetDC(hwnd);
            dialog.processCommand(hwnd, hdc, wParam, lParam);
            ReleaseDC(hwnd, hdc);

            result = TRUE;
          }

          result = FALSE;
        }

      case WM_CLOSE:
        {
          dialog = getDialogWithHWnd(hwnd);
          if (dialog != null) {
            var shouldClose = dialog.processClose();
            dialog.notifyClose();

            if (shouldClose == null) {
              result = DefWindowProc(hwnd, uMsg, wParam, lParam);
            } else if (shouldClose) {
              dialog.destroy();
              result = 0;
            } else {
              result = 0;
            }
          }
        }

      case WM_DESTROY:
        {
          dialog = getDialogWithHWnd(hwnd);
          if (dialog != null) {
            dialog.processDestroy();
            result = DefWindowProc(hwnd, uMsg, wParam, lParam);
          }
        }
      case WM_NCDESTROY:
        {
          dialog = getDialogWithHWnd(hwnd);
          dialog?.notifyDestroyed();
        }

      case WM_CTLCOLORSTATIC:
        {
          result = staticColors?.createSolidBrush(wParam) ?? 0;
        }
      case WM_CTLCOLORBTN:
        {
          result = buttonColors?.createSolidBrush(wParam) ?? 0;
        }
      case WM_CTLCOLORLISTBOX:
        {
          result = listBoxColors?.createSolidBrush(wParam) ?? 0;
        }
      case WM_CTLCOLOREDIT:
        {
          result = editColors?.createSolidBrush(wParam) ?? 0;
        }
      case WM_CTLCOLORSCROLLBAR:
        {
          result = scrollBarColors?.createSolidBrush(wParam) ?? 0;
        }
      case WM_CTLCOLORDLG:
        {
          result = dialogColors?.createSolidBrush(wParam) ?? 0;
        }

      default:
        {
          int? processed;

          dialog = getDialogWithHWnd(hwnd);
          if (dialog != null) {
            processed = dialog.processMessage(hwnd, uMsg, wParam, lParam);
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

  static final Set<Dialog> _dialogs = {};

  /// List of active dialogs.
  static Set<Dialog> get dialogs => UnmodifiableSetView(_dialogs);

  /// Register a [Dialog] (called the constructor).
  static bool registerDialog(Dialog dialog) => _dialogs.add(dialog);

  /// Unregister a [Dialog] (called by [doDestroy]).
  static bool unregisterDialog(Dialog dialog) => _dialogs.remove(dialog);

  /// Returns a [Dialog] with [hwnd].
  /// - See [dialogs].
  static Dialog? getDialogWithHWnd(int hwnd) {
    var d = _dialogs.firstWhereOrNull((w) => w._hwnd == hwnd);
    return d;
  }

  /// Lookup a [Dialog] by `createID` pointer;
  static Dialog? getDialogWithCreateIdPtr(int hwnd, int createIdPtrAddress,
      {required bool nullHwnd}) {
    Pointer<Uint32> createIdPtr;

    try {
      createIdPtr = Pointer<Uint32>.fromAddress(createIdPtrAddress);
    } catch (e, s) {
      _logDialog.severe(
          "Error resolving `createId` pointer to hWnd: $hwnd", e, s);
      return null;
    }

    var createId = createIdPtr.value;

    return getDialogWithCreateId(createId, hwnd: nullHwnd ? null : hwnd);
  }

  /// A [Pointer] to [Dialog.dialogProcDefault].
  static final dialogProcDefaultPtr =
      Pointer.fromFunction<DLGPROC>(Dialog.dialogProcDefault, 0);

  /// Lookup a [Dialog] by `_createID`;
  static Dialog? getDialogWithCreateId(int createId,
      {int? hwnd, String? windowName}) {
    if (createId > 0 && createId <= _createIdCount) {
      return _dialogs.firstWhereOrNull(
        (w) => w._createId == createId && w._hwnd == hwnd,
      );
    }

    return null;
  }

  /// The [Dialog] style.
  int style;

  /// The [Dialog] title.
  String? title;

  /// The [Dialog] [fontName].
  String? fontName;

  /// The [Dialog] [fontSize].
  int? fontSize;

  /// The [Dialog] [items].
  final List<DialogItem> items;

  /// The [Dialog] message processor function.
  /// - Defaults to [Dialog.dialogProcDefault].
  final Pointer<NativeFunction<DLGPROC>> dialogFunction;

  /// The owner of this [Dialog].
  final Window? parent;

  /// The command of this [Dialog] when clicked.
  final void Function(int wParam, int lParam)? onCommand;

  /// The [Dialog] [result] timeout.
  /// - Triggers [finish] on timeout;
  final Duration? timeout;

  /// If `true` set's this [Dialog] frame to dark mode.
  final bool useDarkMode;

  /// The tile color of this [Dialog] frame.
  final int? titleColor;

  Dialog({
    this.style = WINDOW_STYLE.WS_POPUP |
        WINDOW_STYLE.WS_BORDER |
        WINDOW_STYLE.WS_SYSMENU |
        WINDOW_STYLE.WS_VISIBLE,
    this.title,
    super.x,
    super.y,
    super.width,
    super.height,
    this.fontName,
    this.fontSize,
    this.items = const [],
    Pointer<NativeFunction<DLGPROC>>? dialogFunction,
    this.parent,
    this.onCommand,
    this.timeout,
    this.useDarkMode = false,
    this.titleColor,
  }) : dialogFunction = dialogFunction ?? dialogProcDefaultPtr {
    final title = this.title;
    if (title != null && title.isNotEmpty) {
      style |= WINDOW_STYLE.WS_CAPTION;
    }

    final fontName = this.fontName;
    if (fontName != null && fontName.isNotEmpty) {
      style |= DS_SETFONT;
    }

    registerDialog(this);

    setupTimeout();
  }

  Timer? _timeoutTimer;

  /// The [timeout] timer (if running).
  Timer? get timeoutTimer => _timeoutTimer;

  /// Setup [timeoutTimer].
  void setupTimeout() {
    final timeout = this.timeout;
    if (timeout == null) return;

    _timeoutTimer = Timer(timeout, _notifyTimeout);
  }

  bool _timeoutTriggered = false;

  /// Returns `true` if [timeout] was triggered.
  bool get timeoutTriggered => _timeoutTriggered;

  final StreamController<Dialog> _onTimeout = StreamController();

  /// On [timeout] triggered.
  Stream<Dialog> get onTimeout => _onTimeout.stream;

  void _notifyTimeout() {
    if (!_resultSet) {
      _timeoutTriggered = true;
      finish();

      _logDialog.info(() => "Dialog$_hwnd timeout!");

      _onTimeout.add(this);
    }
  }

  static int _createIdCount = 0;

  final int _createId = ++_createIdCount;

  @override
  int get createId => _createId;

  int? _hwnd;

  @override
  int? get hwndIfCreated => _hwnd;

  /// Creates the [Dialog].
  @override
  Future<int> create() async {
    await ensureLoaded();

    final createIdPtr = calloc<Uint32>();
    createIdPtr.value = createId;

    final dialogTemplatePtr = createDialogTemplate();

    final hwnd = createDialogImpl(createIdPtr, dialogTemplatePtr);

    if (hwnd == 0) {
      var errorCode = GetLastError();
      throw StateError("Can't create Dialog> errorCode: $errorCode -> $this");
    }

    _hwnd = hwnd;
    return hwnd;
  }

  /// Dialog creation implementation.
  /// - Calls Win32 [CreateDialogIndirectParam] by default.
  /// - Allows @[override].
  int createDialogImpl(Pointer<Uint32> createIdPtr,
          Pointer<DLGTEMPLATE> dialogTemplatePtr) =>
      CreateDialogIndirectParam(hInstance, dialogTemplatePtr,
          parent?.hwndIfCreated ?? NULL, dialogFunction, createIdPtr.address);

  /// Creates the [DLGTEMPLATE] used by [createDialogImpl].
  Pointer<DLGTEMPLATE> createDialogTemplate() {
    var szBasic = sizeOf<DLGTEMPLATE>();
    var szItems = (sizeOf<DLGITEMTEMPLATE>() + 8) * items.length;

    var sz = szBasic + szItems + 128;

    final Pointer<Uint16> templatePtr = calloc<Uint16>(sz);

    var idx = 0;

    idx += (templatePtr + idx).cast<DLGTEMPLATE>().setDialog(
        style: style,
        title: title ?? '',
        cdit: items.length,
        x: x ?? CW_USEDEFAULT,
        y: y ?? CW_USEDEFAULT,
        cx: width ?? CW_USEDEFAULT,
        cy: height ?? CW_USEDEFAULT,
        fontName: fontName ?? '',
        fontSize: fontSize ?? 0);

    for (var item in items) {
      idx += (templatePtr + idx).cast<DLGITEMTEMPLATE>().setDialogItem(
          style: item.style,
          dwExtendedStyle: item.dwExtendedStyle,
          x: item.x,
          y: item.y,
          cx: item.width,
          cy: item.height,
          id: item.id,
          windowSystemClass: item.windowSystemClass,
          windowClass: item.windowClass,
          text: item.text,
          creationDataBytes: item.creationDataBytes);
    }

    return templatePtr.cast();
  }

  bool _resultSet = false;

  /// Returns `true` if the [result] was set.
  bool get isResultSet => _resultSet;

  R? _result;

  /// The result of the dialog.
  R? get result => _result;

  set result(R? result) {
    _result = result;
    _notifyResult();
  }

  void _notifyResult() {
    _resultSet = true;

    var waitingResult = _waitingResult;
    if (waitingResult != null && !waitingResult.isCompleted) {
      waitingResult.complete(true);
      _waitingResult = null;
    }

    _logDialog.info(() => "Dialog#$_hwnd result: $result");

    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    doClose();
  }

  /// The close procedure. Called when [result] is set.
  /// - Default: call [destroy].
  void doClose() {
    destroy();
  }

  Completer<bool>? _waitingResult;

  /// Waits for the [result].
  Future<bool> waitResult({Duration? timeout}) async {
    if (_resultSet) {
      return true;
    }

    var waitingResult = _waitingResult;
    if (waitingResult != null) {
      return waitingResult.future;
    }

    waitingResult = _waitingResult = Completer<bool>();

    var future = waitingResult.future;

    if (timeout != null) {
      future = future.timeout(timeout, onTimeout: () => false);
    }

    return future;
  }

  /// Calls [waitResult] then returns [result]:
  Future<R?> waitAndGetResult({Duration? timeout}) {
    return waitResult(timeout: timeout).then((_) => result);
  }

  /// Tries to set this [Dialog] [result] to [r] as [R].
  bool setResultDynamic(dynamic r) {
    if (r is int && R == int) {
      var ok = _setResultDynamicImpl(r);
      assert(ok);
      return true;
    }

    if (r is String && R == String) {
      var ok = _setResultDynamicImpl(r);
      assert(ok);
      return true;
    }

    if (_setResultDynamicImpl(r)) {
      return true;
    }

    if (r is List && r.length == 2) {
      var w = r[0];
      var l = r[1];

      if (_setResultDynamicImpl((w, l))) {
        return true;
      }

      if (_setResultDynamicImpl('$w,$l')) {
        return true;
      }

      if (_setResultDynamicImpl(w)) {
        return true;
      }
    }

    return false;
  }

  bool _setResultDynamicImpl(dynamic result) {
    try {
      this.result = result;
      return true;
    } catch (_) {}
    return false;
  }

  /// Finishes this dialog setting its [result].
  void finish([R? result]) {
    this.result = result;
    assert(isResultSet);
  }

  /// Processes a [Dialog] command, usually a button click.
  /// - By default calls [onCommand] if defined, otherwise [setResultDynamic].
  @override
  void processCommand(int hwnd, int hdc, int wParam, int lParam) {
    _logDialog.info(() =>
        '[hwnd: $hwnd, hdc: $hdc] processCommand> wParam: $wParam, lParam: $lParam');

    final onCommand = this.onCommand;

    if (onCommand != null) {
      onCommand(wParam, lParam);
    } else {
      setResultDynamic([wParam, lParam]);
    }
  }

  @override
  bool? processClose() => null;

  @override
  void doDestroy() {
    unregisterDialog(this);
  }

  @override
  String toString() {
    return 'Dialog{style: $style, title: $title, x: $x, y: $y, width: $width, height: $height, fontName: $fontName, fontSize: $fontSize, items: ${items.length}, dialogFunction: $dialogFunction, result: $result, parent: $parent}';
  }
}

/// A [Dialog] item.
class DialogItem {
  final int style;
  final int x;
  final int y;
  final int width;
  final int height;
  final int id;

  final int dwExtendedStyle;
  final int windowSystemClass;
  final String windowClass;
  final String text;

  final List<int> creationDataBytes;

  const DialogItem({
    required this.style,
    this.dwExtendedStyle = 0,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.id,
    this.windowSystemClass = 0,
    this.windowClass = '',
    this.text = '',
    this.creationDataBytes = const [],
  });

  /// A button item.
  factory DialogItem.button(
          {int style = WINDOW_STYLE.WS_CHILD |
              WINDOW_STYLE.WS_VISIBLE |
              WINDOW_STYLE.WS_TABSTOP |
              BS_DEFPUSHBUTTON,
          required int x,
          required int y,
          required int width,
          required int height,
          required int id,
          required String text}) =>
      DialogItem(
        style: style,
        x: x,
        y: y,
        width: width,
        height: height,
        id: id,
        text: text,
      );

  /// A text item.
  factory DialogItem.text(
          {int style = WINDOW_STYLE.WS_CHILD | WINDOW_STYLE.WS_VISIBLE,
          String windowClass = 'static',
          required int x,
          required int y,
          required int width,
          required int height,
          required int id,
          required String text}) =>
      DialogItem(
        style: style,
        x: x,
        y: y,
        width: width,
        height: height,
        id: id,
        windowClass: windowClass,
        text: text,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DialogItem &&
          runtimeType == other.runtimeType &&
          style == other.style &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          id == other.id &&
          dwExtendedStyle == other.dwExtendedStyle &&
          windowSystemClass == other.windowSystemClass &&
          windowClass == other.windowClass &&
          text == other.text &&
          ListEquality<int>()
              .equals(creationDataBytes, other.creationDataBytes);

  @override
  int get hashCode =>
      style.hashCode ^
      x.hashCode ^
      y.hashCode ^
      width.hashCode ^
      height.hashCode ^
      id.hashCode ^
      dwExtendedStyle.hashCode ^
      windowSystemClass.hashCode ^
      windowClass.hashCode ^
      text.hashCode ^
      ListEquality<int>().hash(creationDataBytes);

  @override
  String toString() {
    return 'DialogItem{id: $id, x: $x, y: $y, width: $width, height: $height, style: $style, dwExtendedStyle: $dwExtendedStyle, windowSystemClass: $windowSystemClass, windowClass: $windowClass, creationDataBytes: ${creationDataBytes.length}, text: $text}';
  }
}
