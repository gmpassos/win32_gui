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

const EM_SETBKGNDCOLOR = WM_USER + 67;
const EM_AUTOURLDETECT = WM_USER + 91;
const EM_GETCHARFORMAT = WM_USER + 58;
const EM_SETCHARFORMAT = WM_USER + 68;

const RDW_INVALIDATE = 0x0001;
const RDW_INTERNALPAINT = 0x0002;
const RDW_ERASE = 0x0004;

const RDW_VALIDATE = 0x0008;
const RDW_NOINTERNALPAINT = 0x0010;
const RDW_NOERASE = 0x0020;

const RDW_NOCHILDREN = 0x0040;
const RDW_ALLCHILDREN = 0x0080;

const RDW_UPDATENOW = 0x0100;
const RDW_ERASENOW = 0x0200;

const RDW_FRAME = 0x0400;
const RDW_NOFRAME = 0x0800;
