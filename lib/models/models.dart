// Wire types mirroring remai-central-specs/docs/api/openapi.yaml (camelCase JSON).
// Hand-written fromJson/toJson: no code generation (design D8).

/// Block types, in "Turn into" picker order. Enum names are the wire values.
enum BlockType {
  paragraph('Text'),
  heading1('Heading 1'),
  heading2('Heading 2'),
  heading3('Heading 3'),
  todo('To-do'),
  bulleted('Bulleted list'),
  numbered('Numbered list'),
  quote('Quote'),
  code('Code'),
  divider('Divider');

  const BlockType(this.label);

  /// Name shown in the "Turn into" bar.
  final String label;

  /// Parses a wire value. Unknown values (a newer server) fall back to paragraph
  /// so the text is still editable.
  static BlockType parse(Object? wire) {
    for (final t in values) {
      if (t.name == wire) return t;
    }
    return paragraph;
  }
}

class User {
  const User({required this.id, required this.email, required this.name, required this.createdAt});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
      );

  final String id;
  final String email;
  final String name;
  final String createdAt;
}

class AuthResponse {
  const AuthResponse({required this.token, required this.user});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: json['token'] as String,
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String token;
  final User user;
}

class PageInfo {
  const PageInfo({
    required this.id,
    required this.parentId,
    required this.title,
    required this.icon,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PageInfo.fromJson(Map<String, dynamic> json) => PageInfo(
        id: json['id'] as String,
        parentId: json['parentId'] as String?,
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        updatedAt: json['updatedAt'] as String? ?? '',
      );

  final String id;
  final String? parentId;
  final String title;
  final String icon;
  final String createdAt;
  final String updatedAt;

  PageInfo copyWith({String? title, String? icon}) => PageInfo(
        id: id,
        parentId: parentId,
        title: title ?? this.title,
        icon: icon ?? this.icon,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class Block {
  const Block({required this.id, required this.type, this.text = '', this.checked = false});

  factory Block.fromJson(Map<String, dynamic> json) => Block(
        id: json['id'] as String,
        type: BlockType.parse(json['type']),
        text: json['text'] as String? ?? '',
        checked: json['checked'] as bool? ?? false,
      );

  final String id;
  final BlockType type;
  final String text;
  final bool checked;

  /// The BlockInput shape: exactly the fields the API accepts (unknown fields are rejected).
  Map<String, dynamic> toJson() => {'id': id, 'type': type.name, 'text': text, 'checked': checked};

  Block copyWith({BlockType? type, String? text, bool? checked}) =>
      Block(id: id, type: type ?? this.type, text: text ?? this.text, checked: checked ?? this.checked);

  @override
  bool operator ==(Object other) =>
      other is Block && other.id == id && other.type == type && other.text == text && other.checked == checked;

  @override
  int get hashCode => Object.hash(id, type, text, checked);

  @override
  String toString() => 'Block($id, ${type.name}, ${text.length} chars, checked: $checked)';
}

class PageWithBlocks {
  const PageWithBlocks({required this.page, required this.blocks});

  factory PageWithBlocks.fromJson(Map<String, dynamic> json) => PageWithBlocks(
        page: PageInfo.fromJson(json),
        blocks: [
          for (final b in (json['blocks'] as List<dynamic>? ?? const [])) Block.fromJson(b as Map<String, dynamic>),
        ],
      );

  final PageInfo page;
  final List<Block> blocks;
}

class TrashedPage {
  const TrashedPage({required this.id, required this.title, required this.icon, required this.trashedAt});

  factory TrashedPage.fromJson(Map<String, dynamic> json) => TrashedPage(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        trashedAt: json['trashedAt'] as String? ?? '',
      );

  final String id;
  final String title;
  final String icon;
  final String trashedAt;
}

class SearchResult {
  const SearchResult({
    required this.id,
    required this.parentId,
    required this.title,
    required this.icon,
    required this.snippet,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: json['id'] as String,
        parentId: json['parentId'] as String?,
        title: json['title'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
      );

  final String id;
  final String? parentId;
  final String title;
  final String icon;
  final String snippet;
}

/// Shows an empty (or whitespace-only) page title as "Untitled" (page-management spec).
String displayTitle(String? title) => title == null || title.trim().isEmpty ? 'Untitled' : title;
