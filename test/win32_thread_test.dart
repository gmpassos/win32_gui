@TestOn('windows')
import 'package:test/test.dart';
import 'package:win32_gui/win32_gui.dart';
import 'package:win32_gui/win32_gui_logging.dart';

void main() {
  logToConsole();

  group('Win32Thread', () {
    test('Native Function (OK)', () async {
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      // A function called by a Win32 Thread cannot be a Dart function,
      // as a Dart function cannot be invoked by a thread external
      // to its associated `Isolate`.
      //
      // For a simple test, let's utilize a benign `kernel32` function with
      // a signature compatible to `ThreadProc`, and invoke it with a `null`
      // parameter (`threadParam`), as it will exhibit innocuous behavior.
      var nativeFunctionPtr = kernel32.lookup('K32EmptyWorkingSet');
      print('-- nativeFunctionPtr: $nativeFunctionPtr');

      // Ensure that the function pointer exists:
      expect(nativeFunctionPtr.address, isNot(equals(0)));

      var t = Win32Thread.createThread(
          threadFunction:
              nativeFunctionPtr.cast<NativeFunction<LPTHREAD_START_ROUTINE>>(),
          threadParam: nullptr);

      expect(t, isNotNull);

      expect(t!.hThread, isNot(equals(0)));
      expect(t.threadID, isNot(equals(0)));

      // Wait the Thread to exit:
      var tExited =
          Win32Thread.waitThread(t.hThread, timeout: Duration(seconds: 1));

      expect(tExited, isTrue);
    });

    test('Dart Function (ERROR)', () async {
      var invalidFunction = Pointer.fromFunction<LPTHREAD_START_ROUTINE>(
          _invalidThreadFunction, 0);

      dynamic r;
      try {
        r = Win32Thread.createThread(
            threadFunction: invalidFunction,
            threadParam: 'xyz'.toNativeUtf16());
      } catch (_) {}

      expect(r, isNull);
    }, skip: 'Will perform a FATAL error to the VM');
  });
}

// A Dart function can't be a Win32 Thread function:
int _invalidThreadFunction(Pointer<Utf16> param) {
  return 0;
}
