import 'package:flutter/material.dart';
import 'app_colors.dart';

// ===================== 常用 TextStyle =====================
const TextStyle textTitle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  color: colorTextOnPrimary,
);

const TextStyle textCaption = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w500,
  color: colorTextSecondary,
);

const TextStyle textSecondary = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w400,
  color: colorTextSecondary,
);

const TextStyle textAmountBold = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w400,
  color: colorTextPrimary,
);

const TextStyle textAmountStat = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w700,
  letterSpacing: -1,
  color: colorTextOnPrimary,
);

// ===================== 农历文字 =====================
const TextStyle textLunarDay = TextStyle(
  fontSize: 8,
  fontWeight: FontWeight.w400,
  color: colorLunarText,
);

const TextStyle textLunarFestival = TextStyle(
  fontSize: 8,
  fontWeight: FontWeight.w500,
  color: colorLunarFestival,
);

// ===================== 页面通用 =====================
const TextStyle textBody = TextStyle(fontSize: 14, color: colorTextPrimary);
const TextStyle textHint = TextStyle(fontSize: 14, color: colorTextSecondary);
const TextStyle textPlaceholder = TextStyle(fontSize: 14, color: colorTextPlaceholder);
const TextStyle textListItem = TextStyle(fontSize: 15, color: colorTextPrimary);
const TextStyle textItemSub = TextStyle(fontSize: 12, color: colorTextSecondary);
const TextStyle textCardMeta = TextStyle(fontSize: 13, color: colorTextPrimary);
const TextStyle textToast = TextStyle(fontSize: 13, color: colorTextPrimary);
const TextStyle textCardTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorTextOnPrimary);
const TextStyle textTitleBold = TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colorTextPrimary);
const TextStyle textDialogTitle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colorTextPrimary);
const TextStyle textButtonPrimary = TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: colorTextOnPrimary);
const TextStyle textBalance = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorTextPrimary);
const TextStyle textAccountAmount = TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: colorTextPrimary);
const TextStyle textPickerItem = TextStyle(fontSize: 16, color: colorTextPrimary);
const TextStyle textAmountInput = TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: colorTextPrimary);
const TextStyle textSummaryEmpty = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorTextOnPrimary);

// ===================== 提取自页面内联 =====================
const TextStyle textTabActive = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colorTextOnPrimary);
const TextStyle textTabInactive = TextStyle(fontSize: 18, fontWeight: FontWeight.w400, color: colorTextOnPrimary);
const TextStyle textBalanceLarge = TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: colorTextPrimary);
const TextStyle textAppBarAction = TextStyle(fontSize: 16, color: colorTextOnPrimary);
const TextStyle textAmountFlow = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colorTextPrimary);
const TextStyle textBudgetRemaining = TextStyle(fontSize: 30, fontWeight: FontWeight.w400, letterSpacing: -1, color: colorTextPrimary);
const TextStyle textAmountSummary = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colorTextPrimary);
const TextStyle textPagerButton = TextStyle(fontSize: 14, color: colorTextOnPrimary);
const TextStyle textButtonDefault = TextStyle(fontSize: 15, color: colorTextPrimary);
const TextStyle textButtonDanger = TextStyle(fontSize: 15, color: colorDeleteDark);
