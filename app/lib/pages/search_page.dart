import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索'), backgroundColor: Colors.white, elevation: 0),
      body: const Center(child: Text('搜索账单', style: TextStyle(color: Color(0xFFBBBBBB)))),
    );
  }
}
