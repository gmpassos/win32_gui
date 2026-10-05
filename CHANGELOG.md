## 2.0.0

- Migrated to `win32` 6.x (breaking: `win32_gui` re-exports `package:win32`).
  - See the `win32` [migration guide](https://win32.pub/docs/migration/5xx-to-6xx).

- Breaking changes (typed handles):
  - `WindowBase`:
    - `hwnd`/`hwndIfCreated`: `HWND` (was `int`).
    - `create()`: returns `Future<HWND>`.
    - `build`, `repaint`: `(HWND hwnd, HDC hdc)`.
    - `processCommand`: `(HWND hwnd, HDC hdc, int wParam, int lParam)`.
    - `processMessage`: `(HWND hwnd, int uMsg, int wParam, int lParam)`.
    - `callBuild`/`callRepaint`: `{HDC? hdc}`.
    - `fillRect`, `drawText`, `drawBG`: `HDC hdc`.
    - `drawImage`: `(HDC hdc, HBITMAP hBitmap, ...)`.
  - `Window`:
    - `loadImage`/`loadImageCached`: return `HBITMAP`; `getBitmapDimension(HBITMAP)`.
    - `loadIcon`/`loadIconCached`: return `HICON`.
    - `createWindowImpl`: returns `Win32Result<HWND>`.
    - `windowNameNative`: `PCWSTR?` (`null` when `windowName` is `null`).
  - `WindowClass`:
    - `windowProcDefault` and `WindowProcFunction`: native `WNDPROC` signature
      `(Pointer hwnd, int uMsg, int wParam, int lParam)` (required by `Pointer.fromFunction`).
    - `getWindowWithHWnd`, `getWindowWithCreateId`, `getWindowWithCreateIdPtr`: `HWND`.
    - `classNameNative`: `PCWSTR`.
    - New `createCtlColorBrush` (handles `WM_CTLCOLOR*`).
  - `WindowClassColors.createSolidBrush`: `HBRUSH createSolidBrush(HDC hdc)`.
  - `Dialog`:
    - `dialogProcDefault`: native `DLGPROC` signature `(Pointer hwnd, int uMsg, int wParam, int lParam)`.
    - `getDialogWithHWnd`, `getDialogWithCreateId`, `getDialogWithCreateIdPtr`: `HWND`.
    - `createDialogImpl`: returns `Win32Result<HWND>`.
  - `RichEdit.setTextColor`: `(HDC hdc, int color)`.
  - `Win32Thread`: `createThread` returns `hThread` as `HANDLE`; `waitThread(HANDLE)`.
  - Style parameters with combined-flag defaults are now nullable (same defaults), since `win32` 6.x flags
    can't be combined in `const` expressions: `Dialog(style:)`, `DialogItem.button(style:)`,
    `DialogItem.text(style:)`, `Button(windowStyles:)`.
  - Colors, styles, `wParam`/`lParam` and `hMenu` remain `int` (the `win32` 6.x enum/param types implement `int`).

- Fixes:
  - `setupDarkMode`, `setupTitleColor`, `setWindowRoundedCorners`: catch `WindowsException`
    (`DwmSetWindowAttribute` now throws; caption color and rounded corners require Windows 11).
  - `drawImage`: release the memory DC with `DeleteDC` (was `DeleteObject`).
  - Fixed native memory leaks: `WNDCLASS` in `register()`, `getWindowText`, `setWindowText`,
    `RichEdit.replaceSel` (per `appendText`), `Win32Thread.createThread` thread ID,
    `getSystemDefaultFonts` on error.
  - Error codes come from `Win32Result.error` (captured atomically) instead of a later `GetLastError()` call.

- Fixes (review):
  - `Dialog.dialogProcDefault`: follows the `DLGPROC` contract (returns `TRUE`/`FALSE`, results via
    `DWLP_MSGRESULT`) instead of calling `DefWindowProc` (broke caption drag/close, `WM_NCHITTEST`,
    `WM_QUERYENDSESSION`, and processed messages twice). `WM_CLOSE` destroys the dialog.
  - `Dialog.createDialogTemplate`: the buffer is sized from the actual strings/items
    (`computeDialogTemplateSize`, `DialogItem.computeTemplateSize`); it used to overflow the heap with
    several items or long texts. Null `x`/`y`/`width`/`height` default to `0`/`0`/`defaultWidth`/`defaultHeight`
    (`CW_USEDEFAULT` was truncated to a 16-bit `0`, a zero-sized dialog).
  - `DialogItem.button`: uses the predefined `button` class ordinal (`0x0080`); it was `0` (invalid).
  - `Dialog` lifecycle:
    - The `timeout` timer starts on `create()` (was the constructor).
    - The `result` is set only once (the first result wins); `doClose` only destroys a created, live dialog.
    - Destroyed without a result (e.g. closed by the user): cancels the timer and completes `waitResult` with `false`
      (it used to hang).
    - `waitResult(timeout:)` applies the timeout per caller.
    - `setResultDynamic` checks the type instead of catching any error.
    - The default `processCommand` only sets the result for clicks (`isClickCommand`), not for
      notifications like `EN_SETFOCUS`/`EN_CHANGE`.
  - `WindowClass.windowProcDefault` / `Dialog.dialogProcDefault`: exceptions are caught and logged
    (they were silently converted to `0` at the native callback boundary); `EndPaint`/`ReleaseDC` in `finally`.
  - `WM_CREATE`: no longer crashes (null dereference) for a window without a name (`lpszName == NULL`) or created
    without `lpCreateParams`; looks up the `Window` by `createId` first (an `HWND` can be reused).
  - `WM_CTLCOLOR*`: uses a cached brush (`WindowClassColors.brush`, released by `dispose`) instead of creating a
    GDI brush per message (GDI object leak). Without colors, delegates to `DefWindowProc`.
  - `WindowMessageLoop.runLoopAsync` stops on `WM_QUIT`; `consumeQueue` re-posts a `WM_QUIT` instead of swallowing it.
  - `close()` with the default behavior calls `destroy()` (Win32 `CloseWindow` minimizes a window).
  - `minimize`/`maximize`/`restore`: return the resulting state (`ShowWindow` returns the previous visibility).
  - `showConfirmationDialog(okCancel: true)`: returns `true` for `IDOK` (always returned `false`).
  - `setIcon`: `WM_SETICON` with `ICON_SMALL` (`ICON_SMALL2` is only valid for `WM_GETICON`).
  - `RegisterClass` failures are detected and logged (were reported as success).
  - Children of a destroyed `Window` (e.g. `Button`, `RichEdit`) are notified and unregistered
    (they stayed registered with a stale `HWND`).
  - `onClose`/`onDestroyed`/`onTimeout` are broadcast streams, closed when destroyed.
  - `callRepaint()` outside `WM_PAINT` uses `GetDC`/`ReleaseDC` (was `BeginPaint` with a leaked `PAINTSTRUCT`).
  - `RichEdit.getCharFormat` sets `cbSize` (required by `EM_GETCHARFORMAT`); `appendText` frees its `CHARFORMAT`.
  - Native memory: `createIdPtr` and the dialog template are freed after creation; `dimension`, the rect
    buffer and `windowNameNative` are released by a `NativeFinalizer` (`WindowBase` is `Finalizable`).
  - `Win32Thread.closeThread` (the caller owns the `createThread` handle).
  - Logging: `logAllTo` works (was never called); `LoggerHandler.parent` returns the parent handler;
    `logErrorTo` of a specific logger is used; long logger/isolate names are truncated.
  - `Win32Constants`: removed non-message entries from `wmByID` (`CFM_COLOR`, `SCF_ALL`), added `WM_CTLCOLOR*`,
    removed a top-level `main()` exported by the library.
- New constants: `DWLP_MSGRESULT`, `BN_CLICKED`, `DLG_CLASS_BUTTON`.

- Tests:
  - `test/win32_gui_logic_test.dart`: pure Dart logic (runs on any OS).
  - `test/win32_gui_integration_test.dart`: Windows integration tests for the fixes above.
  - `dart_test.yaml`: `concurrency: 1` (Win32 window classes/message queues are per process/thread).

- CI: `codecov/codecov-action@v5`; a Codecov upload error doesn't fail the build.

- sdk: '>=3.10.0 <4.0.0'

- ffi: ^2.2.0
- win32: ^6.4.0
- collection: ^1.19.1

- lints: ^6.1.0
- test: ^1.31.1
- dependency_validator: ^5.1.0
- coverage: ^1.15.1

## 1.2.0

- sdk: '>=3.7.0 <4.0.0'

- ffi: ^2.1.4
- win32: ^5.12.0
- logging: ^1.3.0
- resource_portable: ^3.1.2
- collection: ^1.19.0

- lints: ^5.1.1
- test: ^1.25.15
- dependency_validator: ^5.0.2
- coverage: ^1.11.1

## 1.1.5

- ffi: ^2.1.2
- win32: ^5.5.0
- collection: ^1.18.0
- lints: ^3.0.0
- test: ^1.25.5
- dependency_validator: ^3.2.3
- coverage: ^1.8.0

## 1.1.4

- `README.md`:
  - Added `Win32 Message Loop` section
- Dart CI: update and optimize jobs.

- ffi: ^2.1.0
- win32: ^5.0.7
- test: ^1.24.6

## 1.1.3

- `WindowMessageLoop`:
  - Added `consumeQueue`.
- `WindowBase`:
  - `destroy`: try `consumeQueue` before retry.
  - `close`: try `consumeQueue` before retry.

## 1.1.2

- `WindowBase`:
  - `destroy`: returns `bool`, retry and warns failed calls.
  - `close`: retry and warns failed calls.

## 1.1.1

- `WindowClassColors`:
  - Added `dialogColors`
- `Dialog`: Added alis `dialogColors` to `WindowClassColors.dialogColors`.

## 1.1.0

- `WindowBase`:
  - Generalize `create`.
- `Window`:
  - Move `setIcon` to `WindowBase`.
- `Dialog.create`: call `ensureLoaded`.

## 1.0.12

- `WindowBase`:
  - Added `requestRepaint`.
  - Removed unnecessary calls to `updateWindow`.

## 1.0.11

- export 'src/win32_dialog.dart';
- Added `DialogItem.button` and `DialogItem.text`.

## 1.0.10

- Improve `README.md` usage code.
- `win32_gui_example.dart`: improve comments.
- `Window`:
  - Added `showMessage`, `showConfirmationDialog` and `showDialog`.
  - Free some pointers.
- New `Dialog`.
- New `WindowBase`: base class for `Window` and `Dialog`.
- New `Win32Thread`.

## 1.0.9

- `WindowMessageLoop.runLoopAsync`: adjust maximum yield time. 

## 1.0.8

- `Window`:
  - Added `setWindowRoundedCorners`
  - Fix `create` behavior.

## 1.0.7

- `Window`:
  - Optimize `setIcon`.i
  - Added `loadIcon` and `loadIconCached`.
- const `TextFormatted`

## 1.0.6

- Fix `RichEdit.defaultFont`.

## 1.0.5

- `TextFormatted`: added `faceName`.
- `RichEdit`:
  - Added `defaultFont` and `defaultSystemFont`.
- `Window`:
  - Added `getSystemDefaultFonts`.
  - Added `minimize`, `maximize`, `restore`, `isMinimized`, `isMaximized` and `getWindowLongPtr`.
  - Change close/processClose to allow abort of operation.
  - Change destroy/processDestroy behavior.

## 1.0.4

- `Window`:
  - Added `onClose` and `processClose`.
  - Renamed `onDestroy` to `onDestroyed` (called after `WM_NCDESTROY`).
  - Added `invalidateRect`.
  - Added `defaultRepaint`: custom `repaint` is only called if `defaultRepaint` is false.
  - Added `getBitmapDimension`.
- `RichEdit`:
  - Optimize `setTextFormatted`.

## 1.0.3

- `Window`: added `redrawWindow`.
- `WindowClassColors`: added `buttonColors`.

## 1.0.2

- `WindowMessageLoop`: optimize `runLoopAsync` yield time.
- Changed `Window.quit` to static.

## 1.0.1

- `WindowMessageLoop.runLoop/runLoopAsync`:
  - Added `condition`.
- `pubspec.yaml`: fix repository.
- `README.md`:
  - Usage example.
  - Added screenshot.
- Adjust example.

## 1.0.0

- Initial version.
