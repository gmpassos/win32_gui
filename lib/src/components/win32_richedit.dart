import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:win32/win32.dart';

import '../win32_constants_extra.dart';
import '../win32_gui_base.dart';

final _log = logging.Logger('RichEdit');

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

  void log(logging.Level level, String method, [String Function()? msg]) =>
      _log.log(level, () {
        if (msg != null) {
          var msgStr = msg();
          return '[hwnd: $hwndIfCreated] $method> $msgStr';
        } else {
          return '[hwnd: $hwndIfCreated] $method()';
        }
      });

  void logInfo(String method, [String Function()? msg]) =>
      log(logging.Level.INFO, method, msg);

  void logWarning(String method, [String Function()? msg]) =>
      log(logging.Level.WARNING, method, msg);

  void logSevere(String method, [String Function()? msg]) =>
      log(logging.Level.SEVERE, method, msg);

  int setTextColor(int hdc, int color) {
    logInfo('setTextColor', () => 'hdc: $hdc, color: $color');
    return SetTextColor(hdc, color);
  }

  int setBkColor(int color) {
    logInfo('setBkColor', () => 'color: $color');
    return sendMessage(EM_SETBKGNDCOLOR, 0, color);
  }

  int setAutoURLDetect(bool autoDetect) {
    logInfo('setAutoURLDetect', () => 'autoDetect: $autoDetect');
    return sendMessage(EM_AUTOURLDETECT, autoDetect ? 1 : 0, 0);
  }

  int setCursorToBottom() {
    logInfo('setCursorToBottom');
    return sendMessage(EM_SETSEL, -2, -1);
  }

  bool scrollVTo(int pos) {
    logInfo('scrollVTo', () => 'pos: $pos');
    return sendMessage(WM_VSCROLL, pos, 0) == 0;
  }

  bool scrollHTo(int pos) => sendMessage(WM_HSCROLL, pos, 0) == 0;

  bool scrollToTop() {
    logInfo('scrollToTop');
    return scrollVTo(SB_TOP);
  }

  bool scrollToBottom() {
    logInfo('scrollToBottom');
    return scrollVTo(SB_BOTTOM);
  }

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

    logInfo('getCharFormat', () => 'range: $range');

    return cf;
  }

  bool setCharFormat(Pointer<CHARFORMAT> cf, [int range = SCF_SELECTION]) {
    logInfo('setCharFormat', () => 'range: $range, cf: #${cf.address}');
    return sendMessage(EM_SETCHARFORMAT, range, cf.address) == 1;
  }

  int replaceSel(String text) {
    logInfo('replaceSel', () => 'text: <<$text>>');
    return sendMessage(EM_REPLACESEL, 0, text.toNativeUtf16().address);
  }

  /// Append a text with different colors.
  void appendText(String text,
      {int? color,
      bool bold = false,
      bool italic = false,
      bool underline = false,
      bool scrollToBottom = true}) {
    final hwnd = this.hwnd;

    final cf = getCharFormat(hwnd);
    final cfRef = cf.ref;

    cfRef.cbSize = sizeOf<CHARFORMAT>();
    cfRef.dwMask = 0;
    cfRef.dwEffects = 0;

    if (color != null) {
      cfRef.dwMask |= CFM_COLOR;
      cfRef.crTextColor = color;
    }

    if (bold) {
      cfRef.dwMask |= CFM_BOLD;
      cfRef.dwEffects |= CFE_BOLD;
    }

    if (italic) {
      cfRef.dwMask |= CFM_ITALIC;
      cfRef.dwEffects |= CFE_ITALIC;
    }

    if (underline) {
      cfRef.dwMask |= CFM_UNDERLINE;
      cfRef.dwEffects |= CFE_UNDERLINE;
    }

    setCharFormat(cf);

    setCursorToBottom();
    replaceSel(text);

    if (scrollToBottom) {
      this.scrollToBottom();
    }
  }

  void appendTextFormatted(TextFormatted textFormatted,
          {bool scrollToBottom = true}) =>
      appendText(textFormatted.text,
          bold: textFormatted.bold,
          italic: textFormatted.italic,
          underline: textFormatted.underline,
          color: textFormatted.color,
          scrollToBottom: scrollToBottom);

  int appendAllTextFormatted(Iterable<TextFormatted> textFormatted,
      {bool scrollToBottom = true}) {
    var list = textFormatted.toList();
    if (list.isEmpty) return 0;

    var beforeLastIdx = list.length - 1;
    for (var i = 0; i < beforeLastIdx; ++i) {
      var tf = list[i];
      appendTextFormatted(tf, scrollToBottom: scrollToBottom);
    }

    {
      var tf = list.last;
      appendTextFormatted(tf, scrollToBottom: scrollToBottom);
    }

    return list.length;
  }

  void setTextFormatted(Iterable<TextFormatted> textFormatted,
      {bool scrollToBottom = true}) {
    setWindowText('');
    appendAllTextFormatted(textFormatted, scrollToBottom: scrollToBottom);
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

class TextFormatted {
  final String text;
  final bool bold;

  final bool italic;

  final bool underline;

  final int? color;

  TextFormatted(this.text,
      {this.bold = false,
      this.italic = false,
      this.underline = false,
      this.color});

  @override
  String toString() =>
      'TextFormatted{bold: $bold, italic: $italic, underline: $underline, color: $color}<<$text>>';
}
