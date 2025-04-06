import 'package:logging/logging.dart' as logging;
import 'package:win32/win32.dart';

import '../win32_gui_base.dart';

final _log = logging.Logger('Win32:Button');

/// A [ChildWindow] of class `button`.
class Button extends ChildWindow {
  static final buttonWindowClass = WindowClass.predefined(className: 'button');

  /// The command of this button when clicked.
  final void Function(int wParam, int lParam)? onCommand;

  Button({
    super.id,
    super.parent,
    required String label,
    super.windowStyles = WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
    int super.x = CW_USEDEFAULT,
    int super.y = CW_USEDEFAULT,
    int super.width = CW_USEDEFAULT,
    int super.height = CW_USEDEFAULT,
    super.bgColor,
    super.defaultRepaint = true,
    this.onCommand,
  }) : super(windowClass: buttonWindowClass, windowName: label);

  /// Calls [onCommand].
  /// See [Window.processCommand].
  @override
  void processCommand(int hwnd, int hdc, int wParam, int lParam) {
    _log.info(
      '[hwnd: $hwnd, hdc: $hdc] processCommand> wParam: $wParam, lParam: $lParam',
    );

    final onCommand = this.onCommand;

    if (onCommand != null) {
      onCommand(wParam, lParam);
    }
  }

  @override
  String toString() {
    return 'Button#$hwndIfCreated{id: $id}';
  }
}
