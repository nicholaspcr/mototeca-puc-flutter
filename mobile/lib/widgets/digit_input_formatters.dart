import 'package:flutter/services.dart';

/// Punctuates a digits-only field while it is typed. The repositories strip
/// the punctuation again before sending.
abstract class DigitInputFormatter extends TextInputFormatter {
  const DigitInputFormatter();

  int get maxDigits;

  String format(String digits);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digits(newValue.text);
    final trimmed = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;
    final formatted = format(trimmed);

    // Keep the cursor after the same digit it followed before formatting.
    final cursor = newValue.selection.end.clamp(0, newValue.text.length);
    final digitsBefore = _digits(newValue.text.substring(0, cursor)).length
        .clamp(0, trimmed.length);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfterDigits(formatted, digitsBefore),
      ),
    );
  }

  static String _digits(String text) => text.replaceAll(RegExp(r'\D'), '');

  static int _offsetAfterDigits(String formatted, int count) {
    if (count == 0) return formatted.isEmpty ? 0 : 1;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (RegExp(r'\d').hasMatch(formatted[i]) && ++seen == count) {
        return i + 1;
      }
    }
    return formatted.length;
  }
}

class PhoneInputFormatter extends DigitInputFormatter {
  const PhoneInputFormatter();

  @override
  int get maxDigits => 11;

  @override
  String format(String digits) => formatPhone(digits);
}

class CnpjInputFormatter extends DigitInputFormatter {
  const CnpjInputFormatter();

  @override
  int get maxDigits => 14;

  @override
  String format(String digits) => formatCnpj(digits);
}

/// `(31) 3333-4444` for a landline, `(31) 99889-1997` for a mobile, and the
/// partial form of either while digits are still missing.
String formatPhone(String digits) {
  if (digits.isEmpty) return '';
  if (digits.length <= 2) return '($digits';
  final area = digits.substring(0, 2);
  final number = digits.substring(2);
  final split = digits.length == 11 ? 5 : 4;
  if (number.length <= split) return '($area) $number';
  return '($area) ${number.substring(0, split)}-${number.substring(split)}';
}

/// `11.222.333/0001-81`, and the partial form while digits are missing.
String formatCnpj(String digits) {
  const separators = {2: '.', 5: '.', 8: '/', 12: '-'};
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (separators[i] case final separator?) out.write(separator);
    out.write(digits[i]);
  }
  return out.toString();
}
