import 'dart:ffi';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart' as logging;
import 'package:win32/win32.dart';

import '../win32_constants_extra.dart';
import '../win32_gui_base.dart';

final _log = logging.Logger('RichEdit');

/// A [ChildWindow] of class `richedit`.
/// - See [loadRichEditLibrary].
/// - See https://learn.microsoft.com/en-us/windows/win32/controls/rich-edit-controls
class RichEdit extends ChildWindow {
  static int? _loadedRichEditLibrary;

  /// Loads `RICHEDIT` library (.dll), and returns its version.
  static int loadRichEditLibrary() =>
      _loadedRichEditLibrary ??= _loadRichEditLibraryImpl();

  static int _loadRichEditLibraryImpl() {
    try {
      DynamicLibrary.open('RICHED20.DLL');
      return 2;
    } catch (_) {}

    try {
      DynamicLibrary.open('RICHED32.DLL');
      return 1;
    } catch (_) {}

    return 0;
  }

  /// Returns the `RICHEDIT` loaded version.
  /// See [loadRichEditLibrary].
  static final int richEditLoadedVersion = loadRichEditLibrary();

  static final windowClassEdit = WindowClass.predefined(
    className: 'edit',
  );

  static final windowClassRich2 = WindowClass.predefined(
    className: 'RichEdit20W',
  );

  static final windowClassRich1 = WindowClass.predefined(
    className: 'RichEdit',
  );

  static String? _defaultSystemFont;

  static String get defaultSystemFont {
    if (_defaultSystemFont != null) return _defaultSystemFont!;
    var sysDefFonts = Window.getSystemDefaultFonts();
    var def = sysDefFonts['caption'] ?? sysDefFonts['message'] ?? 'Arial';
    return _defaultSystemFont = def;
  }

  int _version = -1;

  /// The version of the loaded `RICHEDIT` library.
  int get version => _version;

  String defaultFont;

  RichEdit({
    super.id,
    super.parent,
    int x = CW_USEDEFAULT,
    int y = CW_USEDEFAULT,
    int width = CW_USEDEFAULT,
    int height = CW_USEDEFAULT,
    super.bgColor,
    super.defaultRepaint = false,
    String? defaultFont,
  })  : defaultFont = defaultFont ?? defaultSystemFont,
        super(
          windowClass: switch (richEditLoadedVersion) {
            2 => windowClassRich2,
            1 => windowClassRich1,
            _ => windowClassEdit,
          },
          windowStyles: WINDOW_STYLE.WS_CHILD |
              ES_READONLY |
              WINDOW_STYLE.WS_VISIBLE |
              WINDOW_STYLE.WS_HSCROLL |
              WINDOW_STYLE.WS_VSCROLL |
              WINDOW_STYLE.WS_BORDER |
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

  /// Logs at `RichEdit` [logging.Logger].
  void log(logging.Level level, String method, [String Function()? msg]) =>
      _log.log(level, () {
        if (msg != null) {
          var msgStr = msg();
          return '[hwnd: $hwndIfCreated] $method> $msgStr';
        } else {
          return '[hwnd: $hwndIfCreated] $method()';
        }
      });

  /// `INFO` [log]
  void logInfo(String method, [String Function()? msg]) =>
      log(logging.Level.INFO, method, msg);

  /// `WARNING` [log]
  void logWarning(String method, [String Function()? msg]) =>
      log(logging.Level.WARNING, method, msg);

  /// `SEVERE` [log]
  void logSevere(String method, [String Function()? msg]) =>
      log(logging.Level.SEVERE, method, msg);

  /// Sets the text color of this [RichEdit].
  /// - Calls [SetTextColor].
  int setTextColor(int hdc, int color) {
    logInfo('setTextColor', () => 'hdc: $hdc, color: $color');
    return SetTextColor(hdc, color);
  }

  /// Sets the background color of this [RichEdit].
  /// - Calls [sendMessage] [EM_SETBKGNDCOLOR].
  int setBkColor(int color) {
    logInfo('setBkColor', () => 'color: $color');
    return sendMessage(EM_SETBKGNDCOLOR, 0, color);
  }

  /// Sets this [RichEdit] to auto detect URLs.
  /// - Calls [sendMessage] [EM_AUTOURLDETECT].
  int setAutoURLDetect(bool autoDetect) {
    logInfo('setAutoURLDetect', () => 'autoDetect: $autoDetect');
    return sendMessage(EM_AUTOURLDETECT, autoDetect ? 1 : 0, 0);
  }

  /// Sets this [RichEdit] cursor to bottom.
  /// - Calls [sendMessage] [EM_SETSEL].
  int setCursorToBottom() {
    logInfo('setCursorToBottom');
    return sendMessage(EM_SETSEL, -2, -1);
  }

  /// Scrolls vertically this [RichEdit] to [pos].
  /// - Calls [sendMessage] [WM_VSCROLL].
  bool scrollVTo(int pos) {
    logInfo('scrollVTo', () => 'pos: $pos');
    return sendMessage(WM_VSCROLL, pos, 0) == 0;
  }

  /// Scrolls horizontally this [RichEdit] to [pos].
  /// - Calls [sendMessage] [WM_HSCROLL].
  bool scrollHTo(int pos) => sendMessage(WM_HSCROLL, pos, 0) == 0;

  /// Scrolls this [RichEdit] to top.
  /// - Calls [scrollVTo] [SCROLLBAR_COMMAND.SB_TOP].
  bool scrollToTop() {
    logInfo('scrollToTop');
    return scrollVTo(SCROLLBAR_COMMAND.SB_TOP);
  }

  /// Scrolls horizontally this [RichEdit] to bottom.
  /// - Calls [scrollVTo] [SCROLLBAR_COMMAND.SB_BOTTOM].
  bool scrollToBottom() {
    logInfo('scrollToBottom');
    return scrollVTo(SCROLLBAR_COMMAND.SB_BOTTOM);
  }

  /// Gets the `CHARFORMAT` of this [RichEdit].
  /// - Calls [sendMessage] [EM_GETCHARFORMAT].
  Pointer<CHARFORMAT> getCharFormat([int range = SCF_SELECTION]) {
    final cf = calloc<CHARFORMAT>();
    sendMessage(EM_GETCHARFORMAT, range, cf.address);
    logInfo('getCharFormat', () => 'range: $range');
    return cf;
  }

  /// Sets the [CHARFORMAT] of this [RichEdit].
  /// - Calls [sendMessage] [EM_SETCHARFORMAT].
  bool setCharFormat(Pointer<CHARFORMAT> cf, {int flags = SCF_SELECTION}) {
    logInfo('setCharFormat', () => 'flags: $flags, cf: #${cf.address}');
    return sendMessage(EM_SETCHARFORMAT, flags, cf.address) == 1;
  }

  /// Replaces the selection with [text].
  /// - Calls [sendMessage] [EM_REPLACESEL].
  int replaceSel(String text) {
    logInfo('replaceSel', () => 'text: <<$text>>');
    return sendMessage(EM_REPLACESEL, 0, text.toNativeUtf16().address);
  }

  /// Append a text with different colors to this [RichEdit].
  /// - See: [getCharFormat], [setCharFormat], [setCursorToBottom], [replaceSel], [scrollToBottom].
  void appendText(String text,
      {int? color,
      bool bold = false,
      bool italic = false,
      bool underline = false,
      String? faceName,
      bool scrollToBottom = true}) {
    _onlyTextFormatted = false;
    _appendTextImpl(text,
        color: color,
        bold: bold,
        italic: italic,
        underline: underline,
        faceName: faceName,
        scrollToBottom: scrollToBottom);
  }

  void _appendTextImpl(String text,
      {int? color,
      bool bold = false,
      bool italic = false,
      bool underline = false,
      String? faceName,
      bool scrollToBottom = true}) {
    final cf = getCharFormat();
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

    if (faceName != null && faceName.isNotEmpty) {
      cfRef.dwMask |= CFM_FACE;
      cfRef.szFaceName = faceName;
    } else if (defaultFont.isNotEmpty) {
      cfRef.dwMask |= CFM_FACE;
      cfRef.szFaceName = defaultFont;
    }

    setCharFormat(cf);

    setCursorToBottom();
    replaceSel(text);

    if (scrollToBottom) {
      this.scrollToBottom();
    }
  }

  bool _onlyTextFormatted = true;
  List<TextFormatted>? _allTextFormatted;

  /// Alias to [appendText] passing [textFormatted] attributes.
  void appendTextFormatted(TextFormatted textFormatted,
      {bool scrollToBottom = true}) {
    if (_onlyTextFormatted) {
      var allTextFormatted = _allTextFormatted ??= [];
      allTextFormatted.add(textFormatted);
    }

    _appendTextImpl(textFormatted.text,
        bold: textFormatted.bold,
        italic: textFormatted.italic,
        underline: textFormatted.underline,
        color: textFormatted.color,
        faceName: textFormatted.faceName,
        scrollToBottom: scrollToBottom);
  }

  /// Alias to [appendTextFormatted] passing all [textFormatted] elements.
  int appendAllTextFormatted(Iterable<TextFormatted> textFormatted,
      {bool scrollToBottom = true}) {
    var list = textFormatted.toList();
    if (list.isEmpty) return 0;

    var beforeLastIdx = list.length - 1;
    for (var i = 0; i < beforeLastIdx; ++i) {
      var tf = list[i];
      appendTextFormatted(tf, scrollToBottom: false);
    }

    {
      var tf = list.last;
      appendTextFormatted(tf, scrollToBottom: scrollToBottom);
    }

    return list.length;
  }

  static const _listEquality = ListEquality<TextFormatted>();

  /// Sets this [RichEdit] text with [textFormatted] elements.
  bool setTextFormatted(Iterable<TextFormatted> textFormatted,
      {bool scrollToBottom = true, bool force = false}) {
    var newTextList = textFormatted.toList();

    if (newTextList.isEmpty) {
      setWindowText('');
      _onlyTextFormatted = true;
      _allTextFormatted = null;
      if (scrollToBottom) {
        this.scrollToBottom();
      }
      return true;
    }

    if (!force && _onlyTextFormatted) {
      var allTextFormatted = _allTextFormatted ?? [];
      if (allTextFormatted.isNotEmpty) {
        if (_listEquality.equals(newTextList, allTextFormatted)) {
          if (scrollToBottom) {
            this.scrollToBottom();
          }
          return false;
        }

        var tailSz = newTextList.length - allTextFormatted.length;
        if (tailSz > 0) {
          var headSz = newTextList.length - tailSz;
          assert(headSz > 0);

          var newHead = newTextList.sublist(0, headSz);
          var allTextFormattedHead = allTextFormatted.sublist(0, headSz);

          // Head equals: add only tail (new lines):
          if (_listEquality.equals(newHead, allTextFormattedHead)) {
            var tail = newTextList.sublist(headSz);
            assert(tail.isNotEmpty);
            appendAllTextFormatted(tail, scrollToBottom: scrollToBottom);
            return true;
          }
        }
      }
    }

    setWindowText('');
    _onlyTextFormatted = false;

    appendAllTextFormatted(newTextList, scrollToBottom: scrollToBottom);

    _onlyTextFormatted = true;
    _allTextFormatted = newTextList;

    return true;
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

/// [Struct] for [RichEdit.setCharFormat].
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

  set szFaceName(String name) {
    if (name.length >= LF_FACESIZE) {
      name = name.substring(0, LF_FACESIZE - 1);
    }
    final stringToStore = name.padRight(LF_FACESIZE, '\x00');
    for (var i = 0; i < LF_FACESIZE; i++) {
      _szFaceName[i] = stringToStore.codeUnitAt(i);
    }
  }
}

/// A [RichEdit] text formatted.
class TextFormatted {
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final int? color;
  final String? faceName;

  const TextFormatted(this.text,
      {this.bold = false,
      this.italic = false,
      this.underline = false,
      this.color,
      this.faceName});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextFormatted &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          bold == other.bold &&
          italic == other.italic &&
          underline == other.underline &&
          color == other.color &&
          faceName == other.faceName;

  @override
  int get hashCode =>
      text.hashCode ^
      bold.hashCode ^
      italic.hashCode ^
      underline.hashCode ^
      color.hashCode ^
      faceName.hashCode;

  @override
  String toString() =>
      'TextFormatted{bold: $bold, italic: $italic, underline: $underline, color: $color, faceName: $faceName}<<$text>>';
}
