class Profile {
  final String id;
  final String name;
  final String initial;
  final String? m3uUrl;
  final String? m3uFilePath;
  final int colorIndex;

  Profile({
    required this.id,
    required this.name,
    required this.initial,
    this.m3uUrl,
    this.m3uFilePath,
    this.colorIndex = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'initial': initial,
      'm3uUrl': m3uUrl,
      'm3uFilePath': m3uFilePath,
      'colorIndex': colorIndex,
    };
  }

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      initial: map['initial'] ?? '',
      m3uUrl: map['m3uUrl'],
      m3uFilePath: map['m3uFilePath'],
      colorIndex: map['colorIndex'] ?? 0,
    );
  }
}
