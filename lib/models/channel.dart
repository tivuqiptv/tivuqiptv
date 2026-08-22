class Channel {
  final String id;
  final String name;
  final String url;
  final String category;
  final String? logoUrl;
  final String? tvgId;
  final bool isLive;
  final bool isSeries;
  final String? seriesId;
  final DateTime? addedAt;
  final Map<String, String> httpHeaders;
  final String? sourceProfileId;
  final String? sourceProfileName;
  final String? sourcePlaylistUrl;

  Channel({
    required this.id,
    required this.name,
    required this.url,
    this.category = 'Tümü',
    this.logoUrl,
    this.tvgId,
    this.isLive = true,
    this.isSeries = false,
    this.seriesId,
    this.addedAt,
    this.httpHeaders = const {},
    this.sourceProfileId,
    this.sourceProfileName,
    this.sourcePlaylistUrl,
  });

  Channel copyWith({
    DateTime? addedAt,
    String? category,
    String? sourceProfileId,
    String? sourceProfileName,
    String? sourcePlaylistUrl,
  }) {
    return Channel(
      id: id,
      name: name,
      url: url,
      category: category ?? this.category,
      logoUrl: logoUrl,
      tvgId: tvgId,
      isLive: isLive,
      isSeries: isSeries,
      seriesId: seriesId,
      addedAt: addedAt ?? this.addedAt,
      httpHeaders: httpHeaders,
      sourceProfileId: sourceProfileId ?? this.sourceProfileId,
      sourceProfileName: sourceProfileName ?? this.sourceProfileName,
      sourcePlaylistUrl: sourcePlaylistUrl ?? this.sourcePlaylistUrl,
    );
  }

  factory Channel.fromMap(Map<String, dynamic> map) {
    return Channel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      url: map['url'] ?? '',
      category: map['category'] ?? 'Tümü',
      logoUrl: map['logoUrl'],
      tvgId: map['tvgId'],
      isLive: map['isLive'] ?? true,
      isSeries: map['isSeries'] ?? false,
      seriesId: map['seriesId']?.toString(),
      addedAt: map['addedAt'] == null
          ? null
          : DateTime.tryParse(map['addedAt'].toString())?.toUtc(),
      httpHeaders: Map<String, String>.from(map['httpHeaders'] ?? const {}),
      sourceProfileId: map['sourceProfileId']?.toString(),
      sourceProfileName: map['sourceProfileName']?.toString(),
      sourcePlaylistUrl: map['sourcePlaylistUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'category': category,
      'logoUrl': logoUrl,
      'tvgId': tvgId,
      'isLive': isLive,
      'isSeries': isSeries,
      'seriesId': seriesId,
      'addedAt': addedAt?.toUtc().toIso8601String(),
      'httpHeaders': httpHeaders,
      'sourceProfileId': sourceProfileId,
      'sourceProfileName': sourceProfileName,
      'sourcePlaylistUrl': sourcePlaylistUrl,
    };
  }
}
