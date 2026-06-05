import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FilePicker.skipEntitlementsChecks();
  runApp(const ScoringNidraApp());
}
