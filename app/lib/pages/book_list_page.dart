import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../theme.dart';
import '../models/record.dart';
import '../models/book.dart';
import '../services/record_service.dart';
import '../services/book_service.dart';
import '../utils/formatters.dart';
import '../utils/id.dart';
import '../utils/toast.dart';

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
      await ensureCurrentBookId();
      final loaded = await loadBooks();
      setState(() => _books.addAll(loaded));
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
  int _totalIncome(String bookId) => _records.where((r) => r.bookId == bookId && !r.isExpense).fold(0, (s, r) => s + r.amountCents);
  int _totalExpense(String bookId) => _records.where((r) => r.bookId == bookId && r.isExpense).fold(0, (s, r) => s + r.amountCents);

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
                final book = Book(id: genId(), name: name);
                setState(() => _books.add(book));
                await insertBook(book);
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
                await updateBook(_books[index]);
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
      showToast(context, '至少保留一个账本');
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
              await deleteBook(deletedId);
              if (deletedId == currentBookId.value) {
                await saveCurrentBookId(_books.isNotEmpty ? _books.first.id : null);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: colorDelete)),
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
            foregroundColor: colorTextOnPrimary,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: colorTextOnPrimary.withValues(alpha: 0.3), height: 1),
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
          ? const Center(child: Text('暂无账本，点击右上角 + 新建', style: TextStyle(color: colorTextPlaceholder)))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _books.length,
              separatorBuilder: (_, _) => Container(
                height: 1,
                color: colorDivider,
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
                        padding: const EdgeInsets.fromLTRB(spacingL, 10, spacingL, 10),
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
                                        borderRadius: BorderRadius.circular(radiusSmall),
                                      ),
                                      child: Center(
                                        child: Text(
                                          book.name,
                                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorTextOnPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    if (isCurrent)
                                      const Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Icon(Icons.check, color: colorTextOnPrimary, size: iconSizeSmall),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: spacingL),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('记录数：${_recordCount(book.id)}', style: const TextStyle(fontSize: 13, color: colorTextPrimary)),
                                  const SizedBox(height: spacingXS),
                                  Text('总收入：${formatAmount(_totalIncome(book.id))}', style: const TextStyle(fontSize: 13, color: colorTextPrimary)),
                                  const SizedBox(height: spacingXS),
                                  Text('总支出：${formatAmount(_totalExpense(book.id))}', style: const TextStyle(fontSize: 13, color: colorTextPrimary)),
                                  const SizedBox(height: spacingXS),
                                  Text('总结余：${formatAmount(_totalIncome(book.id) - _totalExpense(book.id))}', style: const TextStyle(fontSize: 13, color: colorTextPrimary)),
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
                                    const SizedBox(width: spacingL),
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

