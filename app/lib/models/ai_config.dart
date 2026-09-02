/// AI 配置模型
class AiConfig {
  String name;
  String url;
  String key;
  String textModel;
  String visionModel;
  String voiceModel;

  AiConfig({
    required this.name,
    required this.url,
    required this.key,
    this.textModel = '',
    this.visionModel = '',
    this.voiceModel = '',
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'url': url,
    'key': key,
    'textModel': textModel,
    'visionModel': visionModel,
    'voiceModel': voiceModel,
  };

  factory AiConfig.fromMap(Map<String, dynamic> m) => AiConfig(
    name: m['name'] as String? ?? '',
    url: m['url'] as String? ?? '',
    key: m['key'] as String? ?? '',
    textModel: m['textModel'] as String? ?? '',
    visionModel: m['visionModel'] as String? ?? '',
    voiceModel: m['voiceModel'] as String? ?? '',
  );
}
