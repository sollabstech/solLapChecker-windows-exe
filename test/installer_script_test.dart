import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Structural checks of the Inno Setup script against the rest of the project.
/// (The compiler itself only runs on Windows; these catch the mistakes that
/// would otherwise only show up when building the installer.)
void main() {
  late String iss;
  late List<String> lines;

  setUpAll(() {
    iss = File('installer/SolLapChecker.iss').readAsStringSync();
    lines = iss.split('\n').map((l) => l.trimRight()).toList();
  });

  /// Lines of one [Section], without comments and blanks.
  List<String> section(String name) {
    final out = <String>[];
    var inside = false;
    for (final l in lines) {
      final t = l.trim();
      if (t.startsWith('[') && t.endsWith(']')) {
        inside = t == '[$name]';
        continue;
      }
      if (inside && t.isNotEmpty && !t.startsWith(';') && !t.startsWith('#')) out.add(t);
    }
    return out;
  }

  String setupValue(String key) {
    final line = section('Setup').firstWhere((l) => l.startsWith('$key='), orElse: () => '');
    return line.isEmpty ? '' : line.substring(key.length + 1);
  }

  test('has every section the installer needs', () {
    for (final s in ['Setup', 'Languages', 'Tasks', 'InstallDelete', 'Files', 'Icons', 'Run', 'UninstallDelete']) {
      expect(iss, contains('[$s]'), reason: s);
    }
  });

  test('every {#Define} that is used is defined', () {
    final defined = RegExp(r'^\s*#define\s+(\w+)', multiLine: true).allMatches(iss).map((m) => m.group(1)).toSet();
    final used = RegExp(r'\{#(\w+)\}').allMatches(iss).map((m) => m.group(1)).toSet();
    expect(used.difference(defined), isEmpty);
    // AppVersion can be overridden from the build script
    expect(iss, contains('#ifndef AppVersion'));
  });

  test('setup identity and output', () {
    expect(setupValue('AppId'), matches(RegExp(r'^\{\{[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}\}$')));
    expect(setupValue('AppName'), '{#AppName}');
    expect(iss, contains('#define AppName       "SolLapChecker"'));
    expect(iss, contains('#define AppPublisher  "Sollabs Tech"'));
    expect(setupValue('OutputBaseFilename'), 'SolLapChecker_Setup');
    expect(setupValue('DefaultDirName'), r'{autopf}\{#AppName}');
  });

  test('64-bit, administrator, Windows 10 or later', () {
    expect(setupValue('PrivilegesRequired'), 'admin');
    expect(setupValue('ArchitecturesInstallIn64BitMode'), 'x64compatible');
    expect(setupValue('ArchitecturesAllowed'), 'x64compatible');
    expect(setupValue('MinVersion'), '10.0');
  });

  test('the installer icon exists and is a real multi-size ICO built from the logo', () {
    final rel = setupValue('SetupIconFile');
    expect(rel, r'..\windows\runner\resources\app_icon.ico');
    final f = File('installer/${rel.replaceAll(r'\', '/')}');
    expect(f.existsSync(), isTrue);

    final b = f.readAsBytesSync();
    final d = ByteData.sublistView(Uint8List.fromList(b));
    expect([d.getUint16(0, Endian.little), d.getUint16(2, Endian.little)], [0, 1]); // ICO header
    final count = d.getUint16(4, Endian.little);
    expect(count, greaterThanOrEqualTo(5));
    final sizes = [for (var i = 0; i < count; i++) b[6 + i * 16] == 0 ? 256 : b[6 + i * 16]];
    expect(sizes, containsAll([16, 32, 48, 256]));
  });

  test('the exe the shortcuts launch is the one the build produces, with the icon embedded', () {
    final exeName = RegExp(r'#define AppExe\s+"([^"]+)"').firstMatch(iss)!.group(1)!;
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    final binary = RegExp(r'set\(BINARY_NAME "([^"]+)"\)').firstMatch(cmake)!.group(1)!;
    expect(exeName, '$binary.exe');

    final rc = File('windows/runner/Runner.rc').readAsStringSync();
    expect(rc, contains(r'IDI_APP_ICON            ICON                    "resources\\app_icon.ico"'));
  });

  test('Start Menu and Desktop shortcuts, the desktop one optional', () {
    final icons = section('Icons');
    expect(icons.any((l) => l.contains(r'{autoprograms}\{#AppName}') && l.contains(r'Filename: "{app}\{#AppExe}"')), isTrue);
    expect(icons.any((l) => l.contains('{uninstallexe}')), isTrue);
    final desktop = icons.firstWhere((l) => l.contains('{autodesktop}'));
    expect(desktop, contains('Tasks: desktopicon'));
    expect(section('Tasks').single, startsWith('Name: "desktopicon"'));
    expect(section('Setup').any((l) => l.startsWith('UninstallDisplayIcon={app}')), isTrue);
  });

  test('ships the Flutter build, the VC++ runtime and the licences', () {
    final files = section('Files');
    expect(files.any((l) => l.contains(r'Source: "{#BuildDir}\*"') && l.contains('recursesubdirs')), isTrue);
    expect(files.any((l) => l.contains(r'Source: "redist\*.dll"')), isTrue);
    expect(files.any((l) => l.contains(r'Source: "licenses\*"') && l.contains(r'DestDir: "{app}\licenses"')), isTrue);
  });

  test('BuildDir is where flutter build windows --release writes', () {
    expect(iss, contains(r'#define BuildDir      "..\build\windows\x64\runner\Release"'));
  });

  test('the build fails early, with a message, when a required file is missing', () {
    for (final f in [r'\smartctl.exe', r'\SolHelper.exe', r'redist\vcruntime140.dll', r'licenses\smartmontools-COPYING.txt']) {
      final guard = RegExp('#if !FileExists\\([^\\n]*${RegExp.escape(f)}"\\)\\s*\\n\\s*#error', multiLine: true);
      expect(guard.hasMatch(iss), isTrue, reason: f);
    }
  });

  test('the tools reach the release folder: CMake copies ..\\tools next to the exe', () {
    final cmake = File('windows/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('SOL_TOOLS_DIR'));
    expect(cmake, contains(r'DESTINATION "${CMAKE_INSTALL_PREFIX}/tools"'));
  });

  test('uninstall removes the program folder but never the user\'s reports', () {
    final u = section('UninstallDelete').join('\n');
    expect(u, contains('{app}'));
    for (final risky in ['Documents', '{userdocs}', 'Reports', '{commondocs}']) {
      expect(u, isNot(contains(risky)), reason: risky);
    }
  });

  test('PawnIO is only offered when its setup was supplied, and never silently', () {
    expect(iss, contains(r'#if FileExists(AddBackslash(SourcePath) + ToolsDir + "\PawnIO_setup.exe")'));
    final run = lines.firstWhere((l) => l.contains('PawnIO_setup.exe"; Description'));
    expect(run, contains('postinstall'));
    expect(run, contains('skipifsilent'));
    expect(run, isNot(contains('/S')));
  });

  test('licence files exist and name smartmontools as GPL', () {
    final notices = File('installer/licenses/THIRD_PARTY_NOTICES.txt').readAsStringSync();
    expect(notices, contains('smartmontools'));
    expect(notices, contains('General Public License'));
    expect(notices, contains('LibreHardwareMonitor'));
    expect(File('installer/licenses/smartmontools-COPYING.txt').readAsStringSync(), contains('GNU GENERAL PUBLIC LICENSE'));
  });

  group('build script', () {
    late String ps;
    setUpAll(() => ps = File('installer/build.ps1').readAsStringSync());

    test('reads the version from pubspec the same way the script expects', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true).firstMatch(pubspec);
      expect(m, isNotNull);
      expect(ps, contains(r"'(?m)^version:\s*(\d+\.\d+\.\d+)'"));
      expect(ps, contains('"/DAppVersion=\$version"'));
    });

    test('builds helper and app, stages the VC++ DLLs, and compiles with ISCC', () {
      expect(ps, contains(r"helper\build.ps1"));
      expect(ps, contains('flutter build windows --release'));
      for (final dll in ['msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']) {
        expect(ps, contains(dll));
      }
      expect(ps, contains('ISCC.exe'));
      expect(ps, contains('Get-FileHash'));
    });

    test('stops with a clear message when smartctl or its licence is missing', () {
      expect(ps, contains('tools\\smartctl.exe is missing'));
      expect(ps, contains('smartmontools-COPYING.txt'));
    });

    test('the helper build script it calls exists', () {
      expect(File('helper/build.ps1').existsSync(), isTrue);
    });
  });
}
