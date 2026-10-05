import 'dart:async';
import 'dart:ffi';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:win32/win32.dart';

import 'win32_constants.dart';
import 'win32_constants_extra.dart';
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

  /// The default [Dialog] [DLGPROC] implementation.
  /// - Takes the native [DLGPROC] parameters (required by [Pointer.fromFunction]).
  static int dialogProcDefault(
    Pointer hwndPtr,
    int uMsg,
    int wParamInt,
    int lParamInt,
  ) {
    final hwnd = HWND(hwndPtr);
    final wParam = WPARAM(wParamInt);
    final lParam = LPARAM(lParamInt);

    _logDialog.info(
      () =>
          'Dialog.dialogProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam',
    );

    // An exception can't cross the native callback boundary
    // (it would be silently converted to `0`): log it.
    try {
      return _dialogProcImpl(hwnd, uMsg, wParam, lParam);
    } catch (e, s) {
      _logDialog.severe(
        'Error processing message: $uMsg (${Win32Constants.wmByID[uMsg]}) ; hwnd: $hwnd',
        e,
        s,
      );
      return FALSE;
    }
  }

  /// A [DLGPROC] returns `TRUE` if it processed the message and `FALSE` to
  /// let the default dialog procedure (`DefDlgProc`) process it.
  /// - It must NOT call [DefWindowProc].
  /// - A message result is set with [DWLP_MSGRESULT].
  /// - Exceptions: `WM_INITDIALOG` and `WM_CTLCOLOR*` return the result directly.
  static int _dialogProcImpl(
    HWND hwnd,
    int uMsg,
    WPARAM wParam,
    LPARAM lParam,
  ) {
    Dialog? dialog;

    switch (uMsg) {
      case WM_INITDIALOG:
        {
          // Lookup `Dialog` by `_createId` first (an `HWND` can be reused):
          if (lParam != 0) {
            dialog = getDialogWithCreateIdPtr(hwnd, lParam, nullHwnd: true);
            dialog?._hwnd = hwnd;
          }

          dialog ??= getDialogWithHWnd(hwnd);

          _logDialog.info(() => "WM_INITDIALOG> hwnd: $hwnd ; window: $dialog");

          if (dialog != null) {
            if (dialog.useDarkMode) {
              dialog.setupDarkMode();
            }

            dialog.setupTitleColor(dialog.titleColor);

            final hdc = GetDC(hwnd);
            try {
              dialog.callBuild(hdc: hdc);
            } finally {
              ReleaseDC(hwnd, hdc);
            }
          }

          // Set the default keyboard focus:
          return TRUE;
        }
      case WM_COMMAND:
        {
          dialog = getDialogWithHWnd(hwnd);
          if (dialog == null) return FALSE;

          final hdc = GetDC(hwnd);
          try {
            dialog.processCommand(hwnd, hdc, wParam, lParam);
          } finally {
            ReleaseDC(hwnd, hdc);
          }

          return TRUE;
        }

      case WM_CLOSE:
        {
          dialog = getDialogWithHWnd(hwnd);
          if (dialog == null) return FALSE;

          var shouldClose = dialog.processClose();
          dialog.notifyClose();

          // `null` (default behavior) or `true`: close.
          // `false`: abort the close.
          if (shouldClose ?? true) {
            dialog.destroy();
          }

          return TRUE;
        }

      case WM_DESTROY:
        {
          getDialogWithHWnd(hwnd)?.processDestroy();
          return FALSE;
        }
      case WM_NCDESTROY:
        {
          getDialogWithHWnd(hwnd)?.notifyDestroyed();
          return FALSE;
        }

      case WM_CTLCOLORSTATIC:
        return WindowClass.createCtlColorBrush(staticColors, wParam);
      case WM_CTLCOLORBTN:
        return WindowClass.createCtlColorBrush(buttonColors, wParam);
      case WM_CTLCOLORLISTBOX:
        return WindowClass.createCtlColorBrush(listBoxColors, wParam);
      case WM_CTLCOLOREDIT:
        return WindowClass.createCtlColorBrush(editColors, wParam);
      case WM_CTLCOLORSCROLLBAR:
        return WindowClass.createCtlColorBrush(scrollBarColors, wParam);
      case WM_CTLCOLORDLG:
        return WindowClass.createCtlColorBrush(dialogColors, wParam);

      default:
        {
          dialog = getDialogWithHWnd(hwnd);
          final processed = dialog?.processMessage(hwnd, uMsg, wParam, lParam);
          if (processed == null) return FALSE;

          SetWindowLongPtr(
            hwnd,
            WINDOW_LONG_PTR_INDEX(DWLP_MSGRESULT),
            processed,
          );
          return TRUE;
        }
    }
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
  static Dialog? getDialogWithHWnd(HWND hwnd) {
    var d = _dialogs.firstWhereOrNull((w) => w._hwnd == hwnd);
    return d;
  }

  /// Lookup a [Dialog] by `createID` pointer;
  static Dialog? getDialogWithCreateIdPtr(
    HWND hwnd,
    int createIdPtrAddress, {
    required bool nullHwnd,
  }) {
    Pointer<Uint32> createIdPtr;

    try {
      createIdPtr = Pointer<Uint32>.fromAddress(createIdPtrAddress);
    } catch (e, s) {
      _logDialog.severe(
        "Error resolving `createId` pointer to hWnd: $hwnd",
        e,
        s,
      );
      return null;
    }

    var createId = createIdPtr.value;

    return getDialogWithCreateId(createId, hwnd: nullHwnd ? null : hwnd);
  }

  /// A [Pointer] to [Dialog.dialogProcDefault].
  static final dialogProcDefaultPtr = Pointer.fromFunction<DLGPROC>(
    Dialog.dialogProcDefault,
    0,
  );

  /// Lookup a [Dialog] by `_createID`;
  static Dialog? getDialogWithCreateId(
    int createId, {
    HWND? hwnd,
    String? windowName,
  }) {
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

  /// - [style] defaults to `WS_POPUP | WS_BORDER | WS_SYSMENU | WS_VISIBLE`.
  Dialog({
    int? style,
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
  }) : style = style ?? (WS_POPUP | WS_BORDER | WS_SYSMENU | WS_VISIBLE),
       dialogFunction = dialogFunction ?? dialogProcDefaultPtr {
    final title = this.title;
    if (title != null && title.isNotEmpty) {
      this.style |= WS_CAPTION;
    }

    final fontName = this.fontName;
    if (fontName != null && fontName.isNotEmpty) {
      this.style |= DS_SETFONT;
    }

    registerDialog(this);
  }

  Timer? _timeoutTimer;

  /// The [timeout] timer (if running).
  Timer? get timeoutTimer => _timeoutTimer;

  /// Setup [timeoutTimer].
  /// - Called by [create], after the [Dialog] is created.
  void setupTimeout() {
    final timeout = this.timeout;
    if (timeout == null || _timeoutTimer != null || _resultSet) return;

    _timeoutTimer = Timer(timeout, _notifyTimeout);
  }

  void _cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  bool _timeoutTriggered = false;

  /// Returns `true` if [timeout] was triggered.
  bool get timeoutTriggered => _timeoutTriggered;

  final StreamController<Dialog> _onTimeout = StreamController.broadcast();

  /// On [timeout] triggered.
  Stream<Dialog> get onTimeout => _onTimeout.stream;

  void _notifyTimeout() {
    _timeoutTimer = null;

    if (!_resultSet && !isDestroyed) {
      _timeoutTriggered = true;

      _logDialog.info(() => "Dialog$_hwnd timeout!");

      // Emit before `finish()`: it may destroy the dialog, closing `_onTimeout`.
      // (Broadcast events are delivered asynchronously, after `finish()`.)
      _onTimeout.add(this);

      finish();
    }
  }

  static int _createIdCount = 0;

  final int _createId = ++_createIdCount;

  @override
  int get createId => _createId;

  HWND? _hwnd;

  @override
  HWND? get hwndIfCreated => _hwnd;

  /// Creates the [Dialog].
  @override
  Future<HWND> create() async {
    await ensureLoaded();

    final createIdPtr = calloc<Uint32>();
    createIdPtr.value = createId;

    final dialogTemplatePtr = createDialogTemplate();

    final Win32Result<HWND> r;
    try {
      r = createDialogImpl(createIdPtr, dialogTemplatePtr);
    } finally {
      // `WM_INITDIALOG` (which reads `createIdPtr`) is processed
      // synchronously, and the template isn't used after the call returns:
      free(createIdPtr);
      free(dialogTemplatePtr);
    }

    final hwnd = r.value;

    if (hwnd.isNull) {
      throw StateError("Can't create Dialog> errorCode: ${r.error} -> $this");
    }

    _hwnd = hwnd;

    setupTimeout();

    return hwnd;
  }

  /// Dialog creation implementation.
  /// - Calls Win32 [CreateDialogIndirectParam] by default.
  /// - Allows @[override].
  Win32Result<HWND> createDialogImpl(
    Pointer<Uint32> createIdPtr,
    Pointer<DLGTEMPLATE> dialogTemplatePtr,
  ) => CreateDialogIndirectParam(
    hInstance,
    dialogTemplatePtr,
    parent?.hwndIfCreated,
    dialogFunction,
    LPARAM(createIdPtr.address),
  );

  /// Default [Dialog] width (dialog units) if [width] is not defined.
  static const defaultWidth = 200;

  /// Default [Dialog] height (dialog units) if [height] is not defined.
  static const defaultHeight = 100;

  /// Returns the size in WORDs (an upper bound) of the template
  /// written by [createDialogTemplate].
  int computeDialogTemplateSize() {
    // `DLGTEMPLATE` (9) + menu (1) + class (1) + title + alignment (1):
    var size = 9 + 1 + 1 + ((title?.length ?? 0) + 1) + 1;

    final fontName = this.fontName;
    if (fontName != null && fontName.isNotEmpty) {
      // Font size (1) + font name:
      size += 1 + (fontName.length + 1);
    }

    for (var item in items) {
      size += item.computeTemplateSize();
    }

    return size;
  }

  /// Creates the [DLGTEMPLATE] used by [createDialogImpl].
  /// - The returned pointer should be released with [free].
  Pointer<DLGTEMPLATE> createDialogTemplate() {
    final sz = computeDialogTemplateSize();

    final Pointer<Uint16> templatePtr = calloc<Uint16>(sz);

    var idx = 0;

    // Note: `DLGTEMPLATE` coordinates are 16-bit dialog units, so
    // `CW_USEDEFAULT` can't be used.
    idx += (templatePtr + idx).cast<DLGTEMPLATE>().setDialog(
      style: style,
      title: title ?? '',
      cdit: items.length,
      x: x ?? 0,
      y: y ?? 0,
      cx: width ?? defaultWidth,
      cy: height ?? defaultHeight,
      fontName: fontName ?? '',
      fontSize: fontSize ?? 0,
    );

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
        creationDataBytes: item.creationDataBytes,
      );
    }

    if (idx > sz) {
      // Should never happen (`computeDialogTemplateSize` is an upper bound):
      throw StateError(
        "Dialog template overflow: written $idx > allocated $sz WORDs",
      );
    }

    return templatePtr.cast();
  }

  bool _resultSet = false;

  /// Returns `true` if the [result] was set.
  bool get isResultSet => _resultSet;

  R? _result;

  /// The result of the dialog.
  R? get result => _result;

  /// Sets the [result] (only once: the first result wins).
  /// - Completes [waitResult], cancels the [timeout] and calls [doClose].
  set result(R? result) {
    if (_resultSet) {
      _logDialog.info(
        () => "Dialog#$_hwnd result already set: $_result (ignoring: $result)",
      );
      return;
    }

    _result = result;
    _notifyResult();
  }

  void _notifyResult() {
    _resultSet = true;

    _completeWaitingResult(true);

    _logDialog.info(() => "Dialog#$_hwnd result: $result");

    _cancelTimeout();

    doClose();
  }

  void _completeWaitingResult(bool resultSet) {
    var waitingResult = _waitingResult;
    if (waitingResult != null && !waitingResult.isCompleted) {
      waitingResult.complete(resultSet);
    }
    _waitingResult = null;
  }

  /// The close procedure. Called when [result] is set.
  /// - Default: call [destroy] (if [created] and not [isDestroyed]).
  void doClose() {
    if (created && !isDestroyed) {
      destroy();
    }
  }

  Completer<bool>? _waitingResult;

  /// Waits for the [result].
  /// - Returns `true` if the [result] was set.
  /// - Returns `false` on [timeout] (for this caller) or if the [Dialog] was
  ///   destroyed without a [result].
  Future<bool> waitResult({Duration? timeout}) {
    if (_resultSet) {
      return Future.value(true);
    }

    if (isDestroyed) {
      return Future.value(false);
    }

    var waitingResult = _waitingResult ??= Completer<bool>();

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
    if (result is! R) return false;
    this.result = result;
    return true;
  }

  /// Finishes this dialog setting its [result].
  void finish([R? result]) {
    this.result = result;
    assert(isResultSet);
  }

  /// Returns `true` if a `WM_COMMAND` [wParam] is a button click
  /// (`BN_CLICKED`), a menu item or an accelerator (keyboard `IDOK`/`IDCANCEL`).
  static bool isClickCommand(int wParam) {
    final notificationCode = (wParam >> 16) & 0xFFFF;
    return notificationCode == BN_CLICKED || notificationCode == 1;
  }

  /// Processes a [Dialog] command, usually a button click.
  /// - By default calls [onCommand] if defined, otherwise [setResultDynamic]
  ///   for click commands (see [isClickCommand]). Other notifications
  ///   (e.g. `EN_CHANGE`, `EN_SETFOCUS`) don't set the [result].
  @override
  void processCommand(HWND hwnd, HDC hdc, int wParam, int lParam) {
    _logDialog.info(
      () =>
          '[hwnd: $hwnd, hdc: $hdc] processCommand> wParam: $wParam, lParam: $lParam',
    );

    final onCommand = this.onCommand;

    if (onCommand != null) {
      onCommand(wParam, lParam);
    } else if (isClickCommand(wParam)) {
      setResultDynamic([wParam, lParam]);
    }
  }

  @override
  bool? processClose() => null;

  @override
  void doDestroy() {
    unregisterDialog(this);

    _cancelTimeout();

    // Destroyed without a result (e.g. closed by the user):
    _completeWaitingResult(false);

    _onTimeout.close();
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
  /// - [style] defaults to `WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON`.
  factory DialogItem.button({
    int? style,
    required int x,
    required int y,
    required int width,
    required int height,
    required int id,
    required String text,
  }) => DialogItem(
    style: style ?? (WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_DEFPUSHBUTTON),
    x: x,
    y: y,
    width: width,
    height: height,
    id: id,
    // The predefined `button` class (ordinal `0x0080`):
    windowSystemClass: DLG_CLASS_BUTTON,
    text: text,
  );

  /// A text item.
  /// - [style] defaults to `WS_CHILD | WS_VISIBLE`.
  factory DialogItem.text({
    int? style,
    String windowClass = 'static',
    required int x,
    required int y,
    required int width,
    required int height,
    required int id,
    required String text,
  }) => DialogItem(
    style: style ?? (WS_CHILD | WS_VISIBLE),
    x: x,
    y: y,
    width: width,
    height: height,
    id: id,
    windowClass: windowClass,
    text: text,
  );

  /// Returns the size in WORDs (an upper bound) of this item in a
  /// [DLGTEMPLATE] (see [Dialog.createDialogTemplate]).
  int computeTemplateSize() {
    // `DLGITEMTEMPLATE` (9):
    var size = 9;

    // Class array: name or `0xFFFF` + ordinal (2):
    size += windowClass.isNotEmpty ? windowClass.length + 1 : 2;

    // Text (title array):
    size += text.length + 1;

    // Creation data: size WORD (1) + bytes:
    size += 1 + (creationDataBytes.length + 1) ~/ 2;

    // DWORD alignment (1):
    size += 1;

    return size;
  }

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
          ListEquality<int>().equals(
            creationDataBytes,
            other.creationDataBytes,
          );

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
