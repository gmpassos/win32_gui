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
