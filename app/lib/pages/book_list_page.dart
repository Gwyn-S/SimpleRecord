import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme.dart';
import '../models/record.dart';

class Book {
  final String id;
  String name;

  Book({required this.id, required this.name});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] as String,
  );
}

class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage> {
  final List<Book> _books = [];
  List<Record> _records = [];

  @override
  void initState() {
    super.initState();
    _loadBooks();
    currentBookId.addListener(_onBookChanged);
    recordsVersion.addListener(_onBookChanged);
  }

  @override
  void dispose() {
    currentBookId.removeListener(_onBookChanged);
    recordsVersion.removeListener(_onBookChanged);
    super.dispose();
  }

  void _onBookChanged() {
    _loadRecords();
    setState(() {});
  }

  Future<void> _loadBooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('books');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List;
        setState(() {
          _books.clear();
          _books.addAll(list.map((e) => Book.fromJson(e as Map<String, dynamic>)));
        });
      }
      if (_books.isEmpty) {
        final defaultBook = Book(id: DateTime.now().millisecondsSinceEpoch.toString(), name: '日常');
        setState(() => _books.add(defaultBook));
        await _saveBooks();
        await saveCurrentBookId(defaultBook.id);
      } else if (_books.length == 1) {
        if (currentBookId.value == null || !_books.any((b) => b.id == currentBookId.value)) {
          await saveCurrentBookId(_books.first.id);
        }
      }
      _loadRecords();
    } catch (e) {
      debugPrint('加载账本失败: $e');
    }
  }

  Future<void> _loadRecords() async {
    final all = await loadRecords();
    setState(() => _records = all);
  }

  int _recordCount(String bookId) => _records.where((r) => r.bookId == bookId).length;
  double _totalIncome(String bookId) => _records.where((r) => r.bookId == bookId && !r.isExpense).fold(0.0, (s, r) => s + r.amount);
  double _totalExpense(String bookId) => _records.where((r) => r.bookId == bookId && r.isExpense).fold(0.0, (s, r) => s + r.amount);

  Future<void> _saveBooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_books.map((e) => e.toJson()).toList());
      await prefs.setString('books', json);
    } catch (e) {
      debugPrint('保存账本失败: $e');
    }
  }

  String _fmt(double v) => v.toStringAsFixed(2);

  void _showAddDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入账本名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _books.add(Book(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name)));
                await _saveBooks();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(int index) {
    final controller = TextEditingController(text: _books[index].name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑账本'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '请输入账本名称',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() => _books[index].name = name);
                await _saveBooks();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(int index) {
    if (_books.length <= 1) {
      final overlay = Overlay.of(context);
      final entry = OverlayEntry(builder: (_) => _Toast(text: '至少保留一个账本'));
      overlay.insert(entry);
      Future.delayed(const Duration(seconds: 2), () => entry.remove());
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账本'),
        content: Text('确定删除「${_books[index].name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final deletedId = _books[index].id;
              setState(() => _books.removeAt(index));
              await _saveBooks();
              if (deletedId == currentBookId.value) {
                await saveCurrentBookId(_books.isNotEmpty ? _books.first.id : null);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<Color>(
          valueListenable: themeColorNotifier,
          builder: (context, color, _) => AppBar(
            title: const Text('账本'),
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: Colors.white.withValues(alpha: 0.3), height: 1),
            ),
            leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: '', onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: _showAddDialog,
              ),
            ],
          ),
        ),
      ),
      body: _books.isEmpty
          ? const Center(child: Text('暂无账本，点击右上角 + 新建', style: TextStyle(color: Color(0xFFBBBBBB))))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _books.length,
              separatorBuilder: (_, _2) => Container(
                height: 1,
                color: const Color(0xFFEEEEEE),
              ),
              itemBuilder: (context, index) {
                final book = _books[index];
                final isCurrent = currentBookId.value == book.id;
                return GestureDetector(
                  onTap: () => saveCurrentBookId(book.id),
                  child: ValueListenableBuilder<Color>(
                    valueListenable: themeColorNotifier,
                    builder: (context, color, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                        child: SizedBox(
                          height: 100,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Column(
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        color: isCurrent ? color : color.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Center(
                                        child: Text(
                                          book.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    if (isCurrent)
                                      const Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Icon(Icons.check, color: Colors.white, size: 16),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('记录数：${_recordCount(book.id)}', style: const TextStyle(fontSize: 13, color: Colors.black)),
                                  const SizedBox(height: 4),
                                  Text('总收入：${_fmt(_totalIncome(book.id))}', style: const TextStyle(fontSize: 13, color: Colors.black)),
                                  const SizedBox(height: 4),
                                  Text('总支出：${_fmt(_totalExpense(book.id))}', style: const TextStyle(fontSize: 13, color: Colors.black)),
                                  const SizedBox(height: 4),
                                  Text('总结余：${_fmt(_totalIncome(book.id) - _totalExpense(book.id))}', style: const TextStyle(fontSize: 13, color: Colors.black)),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 100,
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showEditDialog(index),
                                      child: Icon(Icons.edit, size: 30, color: color),
                                    ),
                                    const SizedBox(width: 16),
                                    GestureDetector(
                                      onTap: () => _showDeleteDialog(index),
                                      child: Icon(Icons.delete_outline, size: 30, color: color),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}
