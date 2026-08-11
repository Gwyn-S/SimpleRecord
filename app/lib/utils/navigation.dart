import 'package:flutter/material.dart';

import '../pages/backup_page.dart';
import '../pages/budget_page.dart';
import '../pages/ledger_list_page.dart';
import '../pages/manual_entry_page.dart';
import '../pages/search_page.dart';
import '../pages/user_page.dart';
import '../models/record.dart';

void openLedgerList(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const LedgerListPage()));

void openBackup(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupPage()));

void openBudget(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetPage()));

void openSearch(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));

void openUser(BuildContext context) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserPage()));

void openEditRecord(BuildContext context, Record record) =>
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ManualEntryPage(initialRecord: record)));
