import 'package:flutter/material.dart';

// TODO: 搜索功能
// - 按日期范围搜索
// - 按分类筛选
// - 按金额区间搜索
// - 关键词备注搜索
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索'), backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: '', onPressed: () => Navigator.pop(context))),
      body: const Center(child: Text('搜索账单', style: TextStyle(color: Color(0xFFBBBBBB)))),
    );
  }
}
