import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'win32_constants_extra.dart';
import 'win32_gui_base.dart';

class RichEdit extends ChildWindow {
  static final int richEditLoadedVersion = WindowClass.loadRichEditLibrary();

  static final windowClassEdit = WindowClass.predefined(
    className: 'edit',
  );

  static final windowClassRich2 = WindowClass.predefined(
    className: 'RichEdit20W',
  );

  static final windowClassRich1 = WindowClass.predefined(
    className: 'RichEdit',
  );

  int _version = -1;

  int get version => _version;

  RichEdit(
      {super.id,
      super.parent,
      int x = CW_USEDEFAULT,
      int y = CW_USEDEFAULT,
      int width = CW_USEDEFAULT,
      int height = CW_USEDEFAULT,
      super.bgColor})
      : super(
          windowClass: switch (richEditLoadedVersion) {
            2 => windowClassRich2,
            1 => windowClassRich1,
            _ => windowClassEdit,
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
    _version = richEditLoadedVersion;
    if (_version <= 0) {
      throw StateError("Can't load `RichEdit` library!");
    }
  }

  int setTextColor(hdc, int color) => SetTextColor(hdc, color);

  int setBkColor(int color) => sendMessage(EM_SETBKGNDCOLOR, 0, color);

  int setAutoURLDetect(bool autoDetect) =>
      sendMessage(EM_AUTOURLDETECT, autoDetect ? 1 : 0, 0);

  int setCursorToBottom() => sendMessage(EM_SETSEL, -2, -1);

  bool scrollVTo(int pos) => sendMessage(WM_VSCROLL, pos, 0) == 0;

  bool scrollHTo(int pos) => sendMessage(WM_HSCROLL, pos, 0) == 0;

  bool scrollToTop() => scrollVTo(SB_TOP);

  bool scrollToBottom() => scrollVTo(SB_BOTTOM);

  Pointer<CHARFORMAT> getCharFormat(int hwnd, [int range = SCF_SELECTION]) {
    final cf = calloc<CHARFORMAT>();

    SendMessage(hwnd, EM_GETCHARFORMAT, range, cf.address);

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

  bool setCharFormat(Pointer<CHARFORMAT> cf, [int range = SCF_SELECTION]) =>
      sendMessage(EM_SETCHARFORMAT, range, cf.address) == 1;

  int replaceSel(Pointer<Utf16> str) =>
      sendMessage(EM_REPLACESEL, 0, str.address);

  /// Append a text with different colors.
  void appendText(int color, String text) {
    final hwnd = this.hwnd;

    var cf = getCharFormat(hwnd);
    cf.ref.cbSize = sizeOf<CHARFORMAT>();
    cf.ref.dwMask = CFM_COLOR; // change color
    cf.ref.crTextColor = color;
    cf.ref.dwEffects = 0;

    setCharFormat(cf);

    var str = text.toNativeUtf16();

    setCursorToBottom();
    replaceSel(str);
    scrollToBottom();
  }

  @override
  String toString() {
    return 'RichEdit#$hwndIfCreated{version: $version}';
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

const LF_FACESIZE = 32;

 */

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
