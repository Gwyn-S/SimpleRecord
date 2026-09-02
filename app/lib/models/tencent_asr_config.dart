/// 腾讯云语音识别密钥配置
class TencentAsrConfig {
  final String secretId;
  final String secretKey;

  const TencentAsrConfig({required this.secretId, required this.secretKey});

  bool get isValid => secretId.isNotEmpty && secretKey.isNotEmpty;
}
