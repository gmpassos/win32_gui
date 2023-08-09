@TestOn('windows')
import 'package:test/test.dart';
import 'package:win32_gui/win32_gui.dart';
import 'package:win32_gui/win32_gui_logging.dart';

int _threadFunction(Pointer<Utf16> param) {
  return 0;
}

void main() {
  logToConsole();

  test('Win32 Thread', () async {
    var t = Win32Thread.createThread(
        threadFunction: Pointer.fromFunction<ThreadProc>(_threadFunction, 0),
        threadParam: 'xyz'.toNativeUtf16());

    expect(t, isNotNull);

    expect(t!.hThread, isNot(equals(0)));
    expect(t.threadID, isNot(equals(0)));

    var tExited =
        Win32Thread.waitThread(t.hThread, timeout: Duration(seconds: 1));
    expect(tExited, isTrue);
  });
}
