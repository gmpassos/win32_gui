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
