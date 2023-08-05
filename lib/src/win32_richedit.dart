import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'win32_constants_extra.dart';
import 'win32_gui_base.dart';

class RichEdit extends Window {
  static final int richEditLoadedVersion = WindowClass.loadRichEditLibrary();

  static final textOutputWindowClass = WindowClass.predefined(
    className: 'edit',
  );

  static final textOutputWindowClassRich2 = WindowClass.predefined(
    className: 'RichEdit20W',
  );

  static final textOutputWindowClassRich1 = WindowClass.predefined(
    className: 'RichEdit',
  );

  late final int version;

  RichEdit(
      {super.parent,
      int x = CW_USEDEFAULT,
      int y = CW_USEDEFAULT,
      int width = CW_USEDEFAULT,
      int height = CW_USEDEFAULT})
      : super(
          windowClass: switch (richEditLoadedVersion) {
            2 => textOutputWindowClassRich2,
            1 => textOutputWindowClassRich1,
            _ => textOutputWindowClass,
          },
          windowStyles: WS_CHILD |
              ES_READONLY |
              WS_VISIBLE |
              WS_HSCROLL |
              WS_VSCROLL |
              WS_BORDER |
              ES_LEFT |
              ES_MULTILINE |
              ES_NOHIDESEL |
              ES_AUTOHSCROLL |
              ES_AUTOVSCROLL,
          x: x,
          y: y,
          width: width,
          height: height,
        ) {
    version = richEditLoadedVersion;
    if (version <= 0) {
      throw StateError("Can't load `RichEdit` library!");
    }
  }

  @override
  void build(int hwnd, int hdc) {
    super.build(hwnd, hdc);

    SetTextColor(hdc, RGB(255, 255, 255));
    SetBkColor(hdc, RGB(42, 40, 38));

    setBkColor(hwnd, RGB(42, 40, 38));
    setAutoURLDetect(hwnd, true);
  }

  @override
  void repaint(int hwnd, int hdc) {
    SetTextColor(hdc, RGB(255, 0, 0)); // red

    setBkColor(hwnd, RGB(16, 16, 16));
    setAutoURLDetect(hwnd, true);

    appendText(hwnd, RGB(255, 0, 0), "Hello\r\n".toNativeUtf16());
    appendText(hwnd, RGB(0, 255, 0), "Word\r\n".toNativeUtf16());
    appendText(hwnd, RGB(0, 255, 255), "Colored Text?".toNativeUtf16());
    appendText(hwnd, RGB(255, 0, 255), " YES\r\n".toNativeUtf16());
  }

  int setBkColor(int hwnd, int color) =>
      SendMessage(hwnd, EM_SETBKGNDCOLOR, 0, color);

  int setAutoURLDetect(int hwnd, bool autoDetect) =>
      SendMessage(hwnd, EM_AUTOURLDETECT, autoDetect ? 1 : 0, 0);

  int setCursorToBottom(int hwnd) => SendMessage(hwnd, EM_SETSEL, -2, -1);

  int scrollTo(int hwnd, int pos) => SendMessage(hwnd, WM_VSCROLL, pos, 0);

  int scrollToBottom(int hwnd) => scrollTo(hwnd, SB_BOTTOM);

  Pointer<CHARFORMAT> getCharFormat(int hwnd, [int range = SCF_SELECTION]) {
    final cf = calloc<CHARFORMAT>();

    var r = SendMessage(hwnd, EM_GETCHARFORMAT, range, cf.address);
    print('!!! getCharFormat> $r');
    print(cf.toString());
    print(cf.ref.cbSize);
    print(cf.ref.dwMask);
    print(cf.ref.dwEffects);
    print(cf.ref.yHeight);
    print(cf.ref.yOffset);
    print(cf.ref.crTextColor);
    print(cf.ref.bCharSet);
    print(cf.ref.bPitchAndFamily);
    print(cf.ref.szFaceName);

    return cf;
  }

  int setCharFormat(int hwnd, Pointer<CHARFORMAT> cf,
          [int range = SCF_SELECTION]) =>
      SendMessage(hwnd, EM_SETCHARFORMAT, range, cf.address);

  int replaceSel(int hwnd, Pointer<Utf16> str) =>
      SendMessage(hwnd, EM_REPLACESEL, 0, str.address);

  // this function is used to output text in different color
  void appendText(int hwnd, int clr, Pointer<Utf16> str) {
    var r0 = setCursorToBottom(hwnd); // move cursor to bottom
    print('!!! setCursorToBottom> $r0');

    var cf = getCharFormat(hwnd); // get default char format
    cf.ref.cbSize = sizeOf<CHARFORMAT>();
    cf.ref.dwMask = CFM_COLOR; // change color
    cf.ref.crTextColor = clr;
    cf.ref.dwEffects = 0;

    var r1 = setCharFormat(hwnd, cf); // set default char format
    print('!!! setCharFormat> $r1');

    var r2 = replaceSel(hwnd, str); // code from google
    print('!!! replaceSel> $r2');

    var r3 = scrollToBottom(hwnd); // scroll to bottom
    print('!!! scrollToBottom> $r3');
  }

  @override
  String toString() {
    return 'RichEdit{version: $version}';
  }
}

/*
typedef struct _charformat
{
	UINT		cbSize;
	_WPAD		_wPad1;
	DWORD		dwMask;
	DWORD		dwEffects;
	LONG		yHeight;
	LONG		yOffset;			/* > 0 for superscript, < 0 for subscript */
	COLORREF	crTextColor;
	BYTE		bCharSet;
	BYTE		bPitchAndFamily;
	TCHAR		szFaceName[LF_FACESIZE];
	_WPAD		_wPad2;
} CHARFORMAT;
 */

//const LF_FACESIZE = 32;

base class CHARFORMAT extends Struct {
  @Uint32()
  external int cbSize;

  @Uint32()
  external int dwMask;

  @Uint32()
  external int dwEffects;

  @Int32()
  external int yHeight;

  @Int32()
  external int yOffset;

  @Uint32()
  external int crTextColor;

  @Uint8()
  external int bCharSet;

  @Uint8()
  external int bPitchAndFamily;

  //external Pointer<Utf16> szFaceName;

  @Array(LF_FACESIZE)
  external Array<Uint16> _szFaceName;

  String get szFaceName {
    final charCodes = <int>[];
    for (var i = 0; i < LF_FACESIZE; i++) {
      if (_szFaceName[i] == 0x00) break;
      charCodes.add(_szFaceName[i]);
    }
    return String.fromCharCodes(charCodes);
  }

  set szFaceName(String value) {
    final stringToStore = value.padRight(LF_FACESIZE, '\x00');
    for (var i = 0; i < LF_FACESIZE; i++) {
      _szFaceName[i] = stringToStore.codeUnitAt(i);
    }
  }
}
