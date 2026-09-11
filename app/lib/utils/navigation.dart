import 'package:flutter/material.dart';

import '../pages/cloud/backup_page.dart';
import '../pages/record/budget_page.dart';
import '../pages/asset/ledger_list_page.dart';
import '../pages/record/manual_entry_page.dart';
import '../pages/record/search_page.dart';
import '../pages/record/tag_manage_page.dart';
import '../pages/record/user_page.dart';
import '../models/data/record.dart';

void openLedgerList(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const LedgerListPage()),
);

void openBackup(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const BackupPage()),
);

void openBudget(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const BudgetPage()),
);

void openTagManage(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const TagManagePage()),
);

void openSearch(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const SearchPage()),
);

void openUser(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const UserPage()),
);

void openEditRecord(BuildContext context, Record record) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => ManualEntryPage(initialRecord: record)),
);
