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
class Dialog<R> {
  static int dialogProcDefault(int hwnd, int uMsg, int wParam, int lParam) {
    var result = 0;

    _logDialog.info(
        'Dialog.dialogProcDefault> hwnd: $hwnd, uMsg: $uMsg (${Win32Constants.wmByID[uMsg]}), wParam: $wParam, lParam: $lParam');

    Dialog? dialog;

    switch (uMsg) {
      case WM_INITDIALOG:
        dialog = getDialogWithHWnd(hwnd);

        // Lookup `Dialog` by `_createId`:
        if (dialog == null && lParam != 0) {
          dialog ??= getDialogWithCreateIdPtr(hwnd, lParam, nullHwnd: true);
        }

        _logDialog.info("WM_INITDIALOG> hwnd: $hwnd ; window: $dialog");

        final hdc = GetDC(hwnd);

        if (dialog != null) {
          dialog.callBuild(hdc: hdc);
        }

        ReleaseDC(hwnd, hdc);

        result = TRUE;
      case WM_COMMAND:
        dialog = getDialogWithHWnd(hwnd);

        if (dialog != null) {
          final hdc = GetDC(hwnd);
          dialog.processCommand(hwnd, hdc, wParam, lParam);
          ReleaseDC(hwnd, hdc);
        }
        break;
      default:
        result = DefWindowProc(hwnd, uMsg, wParam, lParam);
    }

    return result;
  }

  static final Set<Dialog> _dialogs = {};

  static Set<Dialog> get dialogs => UnmodifiableSetView(_dialogs);

  static bool registerDialog(Dialog dialog) => _dialogs.add(dialog);

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

  int style;
  String? title;

  int? x;
  int? y;
  int? width;
  int? height;

  String? fontName;
  int? fontSize;

  final List<DialogItem> items;

  final Pointer<NativeFunction<DlgProc>> dialogFunction;

  final Window? parent;

  /// The command of this [Dialog] when clicked.
  final void Function(int wParam, int lParam)? onCommand;

  Dialog({
    this.style = WS_POPUP | WS_BORDER | WS_SYSMENU,
    this.title,
    this.x,
    this.y,
    this.width,
    this.height,
    this.fontName,
    this.fontSize,
    this.items = const [],
    required this.dialogFunction,
    this.parent,
    this.onCommand,
  }) {
    final title = this.title;
    if (title != null && title.isNotEmpty) {
      style |= WS_CAPTION;
    }

    final fontName = this.fontName;
    if (fontName != null && fontName.isNotEmpty) {
      style |= DS_SETFONT;
    }

    registerDialog(this);
  }

  /// Returns `true` if this [Window] was created.
  bool get created => _hwnd != null;

  int? _hwnd;

  /// The window handler ID (if [created]).
  int get hwnd {
    final hwnd = _hwnd;
    if (hwnd == null) {
      throw StateError(
          "Dialog not created! `hwnd` not defined! Method `create()` should be called before use of `hwnd`.");
    }
    return hwnd;
  }

  /// Returns the window handler ID if [created] or `null`.
  int? get hwndIfCreated => _hwnd;

  static int _createIdCount = 0;

  final int _createId = ++_createIdCount;

  int get createId => _createId;

  /// Creates the [Dialog].
  int create() {
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

    idx += templatePtr.elementAt(idx).cast<DLGTEMPLATE>().setDialog(
        style: WS_POPUP |
            WS_BORDER |
            WS_SYSMENU |
            DS_MODALFRAME |
            DS_SETFONT |
            WS_CAPTION,
        title: 'Sample dialog',
        cdit: items.length,
        x: x ?? CW_USEDEFAULT,
        y: y ?? CW_USEDEFAULT,
        cx: width ?? CW_USEDEFAULT,
        cy: height ?? CW_USEDEFAULT,
        fontName: fontName ?? '',
        fontSize: fontSize ?? 0);

    for (var item in items) {
      idx += templatePtr.elementAt(idx).cast<DLGITEMTEMPLATE>().setDialogItem(
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

  /// Tries to set this [Dialog] [result] to [r] as [R].
  bool setResultDynamic(dynamic r) {
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

  void callBuild({required int hdc}) {
    build(hwnd, hdc);
  }

  void build(int hwnd, int hdc) {}

  /// Processes a [Dialog] command, usually a button click.
  /// - By default calls [onCommand] if defined, otherwise [setResultDynamic].
  void processCommand(int hwnd, int hdc, int wParam, int lParam) {
    _logDialog.info(
        '[hwnd: $hwnd, hdc: $hdc] processCommand> wParam: $wParam, lParam: $lParam');

    final onCommand = this.onCommand;

    if (onCommand != null) {
      onCommand(wParam, lParam);
    } else {
      setResultDynamic([wParam, lParam]);
    }
  }

  @override
  String toString() {
    return 'Dialog{style: $style, title: $title, x: $x, y: $y, width: $width, height: $height, fontName: $fontName, fontSize: $fontSize, items: $items, dialogFunction: $dialogFunction, result: $result, parent: $parent}';
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
