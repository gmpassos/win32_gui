import 'package:win32/win32.dart';

// ignore_for_file: constant_identifier_names

const CFM_COLOR = 0x40000000;
const CFM_FACE = 0x20000000;

const CFE_BOLD = 1;
const CFE_ITALIC = 2;
const CFE_UNDERLINE = 4;

const CFM_BOLD = 1;
const CFM_ITALIC = 2;
const CFM_UNDERLINE = 4;

const SCF_ALL = 4;
const SCF_DEFAULT = 0;
const SCF_SELECTION = 1;

/// `SetWindowLongPtr` index of a dialog procedure message result.
const DWLP_MSGRESULT = 0;

/// Button notification code (`HIWORD(wParam)` of `WM_COMMAND`).
const BN_CLICKED = 0;

/// The predefined `button` system class ordinal (dialog templates).
const DLG_CLASS_BUTTON = 0x0080;

const EM_SETBKGNDCOLOR = WM_USER + 67;
const EM_AUTOURLDETECT = WM_USER + 91;
const EM_GETCHARFORMAT = WM_USER + 58;
const EM_SETCHARFORMAT = WM_USER + 68;
