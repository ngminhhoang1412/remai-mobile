import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'api/token_storage.dart';
import 'app.dart';
import 'state/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionState(
    storage: SecureTokenStorage(),
    httpClient: http.Client(),
    baseUrl: configuredApiUrl,
  );
  runApp(RemaiApp(session: session));
}
