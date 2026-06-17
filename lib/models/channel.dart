class Channel {
  final int id;
  final String name;
  final String shortName;
  final String category;
  final String playerType;
  final String streamUrl;
  final String webUrl;
  final String logoUrl;
  final Map<String, String> httpHeaders;
  final bool isActive;

  Channel({
    required this.id,
    required this.name,
    required this.shortName,
    required this.category,
    required this.playerType,
    required this.streamUrl,
    required this.webUrl,
    required this.logoUrl,
    required this.httpHeaders,
    required this.isActive,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      shortName: json['shortName'] ?? '',
      category: json['category'] ?? '',
      playerType: json['playerType'] ?? 'hls',
      streamUrl: json['streamUrl'] ?? '',
      webUrl: json['webUrl'] ?? '',
      logoUrl: json['logoUrl'] ?? '',
      httpHeaders: Map<String, String>.from(json['httpHeaders'] ?? {}),
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'shortName': shortName,
      'category': category,
      'playerType': playerType,
      'streamUrl': streamUrl,
      'webUrl': webUrl,
      'logoUrl': logoUrl,
      'httpHeaders': httpHeaders,
      'isActive': isActive,
    };
  }

  bool get isWebView => playerType.toLowerCase() == 'webview';

  bool get isHls => playerType.toLowerCase() == 'hls';

  String get playerLabel {
    final type = playerType.trim().toUpperCase();

    if (type.isEmpty) {
      return 'HLS';
    }

    return type;
  }
}