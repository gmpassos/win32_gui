import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// ignore_for_file: constant_identifier_names

/// Handles Win32 Thread creation:
class Win32Thread {
  /// Creates a Win32 Thread.
  /// - [threadFunction] is the entrypoint function of the Thread. Note that this can't
  ///   be a Dart function, since it can't be called from a thread external to its `Isolate`.
  /// - [threadParam] is an optional parameter to be passed to [threadFunction].
  static ({int threadID, int hThread})? createThread(
      {required Pointer<NativeFunction<LPTHREAD_START_ROUTINE>> threadFunction,
      Pointer<NativeType>? threadParam,
      int flags = 0}) {
    final threadIdPtr = calloc<Uint32>();

    var hThread = CreateThread(
      nullptr,
      0,
      threadFunction,
      threadParam ?? nullptr,
      flags,
      threadIdPtr,
    );

    if (hThread == NULL) {
      return null;
    }

    var threadId = threadIdPtr.value;

    return (threadID: threadId, hThread: hThread);
  }

  static const WAIT_OBJECT_0 = 0x00000000;
  static const WAIT_TIMEOUT = 0x00000102;
  static const WAIT_ABANDONED = 0x00000080;
  static const WAIT_FAILED = 0xFFFFFFFF;

  /// Waits a thread to exit.
  /// - Calls Win32 [WaitForSingleObject].
  /// - Returns `null` if failed.
  /// - Returns `true` if thread exited.
  /// - Returns `false` on timeout.
  static bool? waitThread(int hThread, {Duration? timeout}) {
    int timeoutMs;
    if (timeout != null) {
      timeoutMs = timeout.inMilliseconds;
      if (timeoutMs < 0) {
        timeoutMs = 0;
      }
    } else {
      timeoutMs = INFINITE;
    }

    var r = WaitForSingleObject(hThread, timeoutMs);

    if (r == WAIT_OBJECT_0) {
      return true;
    } else if (r == WAIT_TIMEOUT) {
      return false;
    }

    return null;
  }
}
