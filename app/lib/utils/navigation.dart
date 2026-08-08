import 'package:flutter/material.dart';

import '../pages/backup_page.dart';
import '../pages/book_list_page.dart';
import '../pages/manual_entry_page.dart';
import '../pages/search_page.dart';
import '../pages/user_page.dart';
import '../models/record.dart';

void openBookList(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BookListPage()));

void openBackup(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage()));

void openSearch(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));

void openUser(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage()));

void openEditRecord(BuildContext context, Record record) =>
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ManualEntryPage(initialRecord: record)));
