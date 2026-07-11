import 'package:flutter/material.dart';

class BookListPage extends StatelessWidget {
  const BookListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账本'), backgroundColor: Colors.white, elevation: 0),
      body: const Center(child: Text('账本管理', style: TextStyle(color: Color(0xFFBBBBBB)))),
    );
  }
}
