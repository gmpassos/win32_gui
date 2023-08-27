# win32_gui

[![pub package](https://img.shields.io/pub/v/win32_gui.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/win32_gui)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/gmpassos/win32_gui/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/gmpassos/win32_gui/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/win32_gui?logo=git&logoColor=white)](https://github.com/gmpassos/win32_gui/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/win32_gui/latest?logo=git&logoColor=white)](https://github.com/gmpassos/win32_gui/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/win32_gui?logo=git&logoColor=white)](https://github.com/gmpassos/win32_gui/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/win32_gui?logo=github&logoColor=white)](https://github.com/gmpassos/win32_gui/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/win32_gui?logo=github&logoColor=white)](https://github.com/gmpassos/win32_gui)
[![License](https://img.shields.io/github/license/gmpassos/win32_gui?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/win32_gui/blob/master/LICENSE)

Win32 API GUI in Object-Oriented style with some helpers. Uses package [win32] and [dart:ffi]. 

[win32]: https://pub.dev/packages/win32
[dart:ffi]: https://api.dart.dev/stable/latest/dart-ffi/dart-ffi-library.html

## Screenshot

[Example](https://github.com/gmpassos/win32_gui/blob/master/example/win32_gui_example.dart) screenshot:

<img alt="Example screenshot" width="640" src="https://raw.githubusercontent.com/gmpassos/win32_gui/master/example/example-screenshot.png" />

## Usage

Here's a simple Hello World window:

```dart
import 'dart:io';

import 'package:win32_gui/win32_gui.dart';

Future<void> main() async {
  // Your custom main Window class (declared bellow):
  var mainWindow = MainWindow(
    width: 640,
    height: 480,
  );

  // Create the window:
  await mainWindow.create();
  
  // Exit when the Window is closed and destroyed:
  // See `MainWindow.processClose` below:
  mainWindow.onDestroy.listen((window) {
    print('-- Window Destroyed> $window');
    exit(0);
  });

  // Show the main Window:
  mainWindow.show();

  // Run the Win32 Window message loop.
  await Window.runMessageLoopAsync();
}

// A custom main Window:
class MainWindow extends Window {
  // Declare the main window custom class:
  static final mainWindowClass = WindowClass.custom(
    className: 'mainWindow',
    windowProc: Pointer.fromFunction<WindowProc>(mainWindowProc, 0),
    bgColor: RGB(255, 255, 255),
    useDarkMode: true,
    titleColor: RGB(32, 32, 32),
  );

  // Redirect to default implementation [WindowClass.windowProcDefault].
  static int mainWindowProc(int hwnd, int uMsg, int wParam, int lParam) =>
          WindowClass.windowProcDefault(
                  hwnd, uMsg, wParam, lParam, mainWindowClass);
  
  MainWindow({super.width, super.height})
          : super(
    defaultRepaint: false, // Tells that `repaint()` below will be used. 
    windowName: 'Win32 GUI - Example', // The Window title.
    windowClass: mainWindowClass,
    windowStyles: WS_MINIMIZEBOX | WS_SYSMENU,
  ) ;

  late final String imageDartLogoPath;
  late final String iconDartLogoPath;
  
  // Load resources (called by `create()`):
  @override
  Future<void> load() async {
    imageDartLogoPath = await Window.resolveFilePath(
            'package:win32_gui/resources/dart-logo.bmp');
    
    iconDartLogoPath = await Window.resolveFilePath(
            'package:win32_gui/resources/dart-icon.ico');
  }

  // Called when processing a `WM_CREATE` message (generated by `create()`):
  @override
  void build(int hwnd, int hdc) {
    super.build(hwnd, hdc);

    SetTextColor(hdc, RGB(255, 255, 255));
    SetBkColor(hdc, RGB(96, 96, 96));

    // Sets the Window icon: 
    setIcon(iconDartLogoPath);
  }
  
  // Customize close operation:
  @override
  bool? processClose() {
    // Inform default close behavior (`destroy()` Window):
    return null;
  }
  
  // Custom repaint. Called when processing a `WM_PAINT` message and `this.defaultRepaint = false`:
  @override
  void repaint(int hwnd, int hdc) {
    // Loads a 24-bits Bitmap:
    var hBitmap = loadImageCached(imageDartLogoPath);
    // Get the Bitmap dimensions:
    var imgDimension = getBitmapDimension(hBitmap);

    // Valid Bitmap:
    if (imgDimension != null) {
      var imgW = imgDimension.width;
      var imgH = imgDimension.height;
      
      // Center image horizontally:
      final x = (dimensionWidth - imgW) ~/ 2;
      final y = 10;

      // Draws the Bitmap copying its bytes to this Window.
      drawImage(hdc, hBitmap, x, y, imgW, imgH);
    }
  }
}
```

# Win32 Message Loop

A [win32] application requires a message loop.
Depending on the implementation of the [win32] message loop, it will block
the Dart VM loop, responsible for dispatching `Future` executions
and `Isolate` messages:

```dart
  final msg = calloc<MSG>();
  while (GetMessage(msg, NULL, 0, 0) != 0) {
    TranslateMessage(msg);
    DispatchMessage(msg);
  }
  free(msg);
```

The code above is equivalent to calling `Window.runMessageLoop()`,
and it will block any other Dart code from being executed,
such as timers, listeners, or any dispatched `Future`.


To circumvent this significant issue, you can make use of
the `Window.runMessageLoopAsync()` function.
This function not only dispatches [win32] messages but also enables
the dispatch of Dart code by intermittently yielding control.

```dart
  // Run the Win32 Window message loop until the application completes.
  await Window.runMessageLoopAsync();
```

If you need to run the [win32] loop for a specific duration:

```dart
  // Run the Win32 Window message loop for 10s:
  await Window.runMessageLoopAsync(timeout: Duration(seconds: 10));
```

...or while a certain condition holds true. 

```dart
  // Run the Win32 Window message loop while the `mainWindow` is minimized:
  await Window.runMessageLoopAsync(condition: () => mainWindow.isMinimized);
```

# Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

# Contribution

Your assistance and involvement within the open-source community is not only valued but vital.
Here's how you can contribute:

- Found an issue?
    - Please fill a bug report with details.
- Wish a feature?
    - Open a feature request with use cases.
- Are you using and liking the project?
    - Advocate for the project: craft an article, share a post, or offer a donation.
- Are you a developer?
    - Fix a bug and send a pull request.
    - Implement a new feature.
    - Improve the Unit Tests.
- Already offered your support?
    - **Sincere gratitude from myself, fellow contributors, and all beneficiaries of this project!**

*By donating one hour of your time, you can make a significant contribution,
as others will also join in doing the same. Just be a part of it and begin with your one hour.*

[tracker]: https://github.com/gmpassos/win32_gui/issues

# Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

[Apache License - Version 2.0][apache_license]

[apache_license]: https://www.apache.org/licenses/LICENSE-2.0.txt
