import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// RFC 4122 v4 UUID for client-created block ids (kept by the server, see page-content spec).
String newId() => _uuid.v4();
