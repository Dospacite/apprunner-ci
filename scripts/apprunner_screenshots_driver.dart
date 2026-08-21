import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final outputPath = Platform.environment['APPRUNNER_SCREENSHOT_DIR'];
  if (outputPath == null || outputPath.isEmpty) {
    throw StateError('APPRUNNER_SCREENSHOT_DIR is required.');
  }

  final output = Directory(outputPath)..createSync(recursive: true);
  final captures = <Map<String, Object>>[];
  final names = <String>{};

  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(name)) {
        throw StateError('Invalid screenshot name: $name');
      }
      if (!names.add(name)) {
        throw StateError('Duplicate screenshot name: $name');
      }
      if (bytes.length < 8 ||
          bytes[0] != 0x89 ||
          bytes[1] != 0x50 ||
          bytes[2] != 0x4e ||
          bytes[3] != 0x47) {
        throw StateError('Screenshot $name is not a PNG.');
      }

      final filename = '$name.png';
      File('${output.path}/$filename').writeAsBytesSync(bytes, flush: true);
      captures.add({
        'name': name,
        'ordinal': captures.length,
        'filename': filename,
      });
      return true;
    },
    responseDataCallback: (_) async {
      if (captures.isEmpty) {
        throw StateError('The screenshot journey did not capture any screens.');
      }
      final pending = File('${output.path}/captures.json.tmp');
      pending.writeAsStringSync(
        jsonEncode({'version': 1, 'screenshots': captures}),
        flush: true,
      );
      pending.renameSync('${output.path}/captures.json');
    },
    writeResponseOnFailure: false,
  );
}
