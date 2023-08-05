import 'package:win32/win32.dart';

import 'win32_gui_base.dart';

class Button extends ChildWindow {
  static final buttonWindowClass = WindowClass.predefined(
    className: 'button',
  );

  final void Function(int lParam)? onCommand;

  Button(
      {required super.id,
      super.parent,
      required String label,
      int windowStyles = WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
      int x = CW_USEDEFAULT,
      int y = CW_USEDEFAULT,
      int width = CW_USEDEFAULT,
      int height = CW_USEDEFAULT,
      this.onCommand})
      : super(
          windowClass: buttonWindowClass,
          windowName: label,
          windowStyles: windowStyles,
          x: x,
          y: y,
          width: width,
          height: height,
        );

  @override
  void processCommand(int hwnd, int hdc, int lParam) {
    final onCommand = this.onCommand;

    if (onCommand != null) {
      onCommand(lParam);
    }
  }

  @override
  String toString() {

    return 'Button{id: $id}';
  }
}
