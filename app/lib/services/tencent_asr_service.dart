import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../models/tencent_asr_config.dart';

/// 构建注入的腾讯云语音识别密钥（--dart-define-from-file 注入，密件不入 Git）。
/// 发布/分发版本内置，用户无需手动填写。
const _envAsrSecretId = String.fromEnvironment('TENCENT_ASR_SECRET_ID');
const _envAsrSecretKey = String.fromEnvironment('TENCENT_ASR_SECRET_KEY');
const _host = 'asr.tencentcloudapi.com';
final _dio = Dio();

/// 加载腾讯云语音识别密钥（发布版由构建注入，配置恒存在）。
Future<TencentAsrConfig> loadAsrConfig() async =>
    TencentAsrConfig(secretId: _envAsrSecretId, secretKey: _envAsrSecretKey);

/// 调用腾讯云一句话识别，返回识别文本。
/// [audioFile] 建议为 16k 采样率 wav/amr 格式。
Future<String> recognizeSpeech({
  required TencentAsrConfig config,
  required File audioFile,
}) async {
  final bytes = await audioFile.readAsBytes();
  return _callSentenceRecognition(config, base64Encode(bytes), bytes.length);
}

Future<String> _callSentenceRecognition(
  TencentAsrConfig config,
  String data,
  int dataLen,
) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final sessionId = const Uuid().v4();

  final body = jsonEncode({
    'EngSerViceType': '16k_zh',
    'SourceType': 1,
    'VoiceFormat': 'wav',
    'Data': data,
    'DataLen': dataLen,
    'ProjectId': 0,
    'SubServiceType': 2,
    'UsrAudioKey': sessionId,
  });

  final headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Host': _host,
    'X-TC-Action': 'SentenceRecognition',
    'X-TC-Version': '2019-06-14',
    'X-TC-Timestamp': '$timestamp',
    'Authorization': _tc3Signature(config, timestamp, body),
  };

  try {
    final response = await _dio.post(
      'https://$_host/',
      options: Options(
        headers: headers,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
      data: body,
    );
    final data = response.data;
    if (data is Map && data['Response'] is Map) {
      final resp = data['Response'] as Map;
      final error = resp['Error'];
      if (error is Map) {
        throw Exception('腾讯云语音识别失败：${error['Code']} ${error['Message']}');
      }
      final result = resp['Result'] as String? ?? '';
      if (result.isEmpty) {
        throw Exception('未识别到语音内容');
      }
      return result;
    }
    throw Exception('腾讯云语音识别响应异常');
  } on DioException catch (e) {
    final d = e.response?.data;
    if (d is Map && d['Response'] is Map) {
      final resp = d['Response'] as Map;
      final error = resp['Error'];
      if (error is Map) {
        throw Exception('腾讯云语音识别失败：${error['Code']} ${error['Message']}');
      }
      throw Exception('腾讯云语音识别失败：$resp');
    }
    throw Exception('腾讯云语音识别请求失败：${e.message}');
  }
}

/// 腾讯云 TC3-HMAC-SHA256 签名
String _tc3Signature(TencentAsrConfig config, int timestamp, String body) {
  final date = DateTime.fromMillisecondsSinceEpoch(
    timestamp * 1000,
    isUtc: true,
  ).toIso8601String().split('T').first;
  const service = 'asr';
  const algorithm = 'TC3-HMAC-SHA256';

  final hashedBody = sha256.convert(utf8.encode(body)).toString();
  final canonicalRequest = [
    'POST',
    '/',
    '',
    'content-type:application/json; charset=utf-8',
    'host:$_host',
    'x-tc-action:sentencerecognition',
    '',
    'content-type;host;x-tc-action',
    hashedBody,
  ].join('\n');

  final stringToSign = [
    algorithm,
    '$timestamp',
    '$date/$service/tc3_request',
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  List<int> hmacSha256(List<int> key, String data) {
    return Hmac(sha256, key).convert(utf8.encode(data)).bytes;
  }

  final secretDate = hmacSha256(utf8.encode('TC3${config.secretKey}'), date);
  final secretService = hmacSha256(secretDate, service);
  final secretSigning = hmacSha256(secretService, 'tc3_request');
  final signature = Hmac(
    sha256,
    secretSigning,
  ).convert(utf8.encode(stringToSign)).toString();

  return '$algorithm Credential=${config.secretId}/$date/$service/tc3_request, '
      'SignedHeaders=content-type;host;x-tc-action, Signature=$signature';
}
