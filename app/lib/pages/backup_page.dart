import 'package:flutter/material.dart';

class BackupPage extends StatelessWidget {
  const BackupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份'), backgroundColor: Colors.white, elevation: 0),
      body: const Center(child: Text('备份设置', style: TextStyle(color: Color(0xFFBBBBBB)))),
    );
  }
}
