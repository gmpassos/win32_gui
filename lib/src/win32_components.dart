import 'package:win32/win32.dart';

import 'win32_gui_base.dart';

class Button extends Window {
  static final buttonWindowClass = WindowClass.predefined(
    className: 'button',
  );

  Button(
      {super.parent,
      int x = CW_USEDEFAULT,
      int y = CW_USEDEFAULT,
      int width = CW_USEDEFAULT,
      int height = CW_USEDEFAULT})
      : super(
          windowClass: buttonWindowClass,
          windowStyles: WS_TABSTOP | WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON,
          x: x,
          y: y,
          width: width,
          height: height,
        );

  @override
  String toString() {
    return 'Button{}';
  }
}
