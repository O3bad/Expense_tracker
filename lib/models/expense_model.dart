import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String? id;
  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String notes;

  Expense({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    this.notes = '',
  });

  static DateTime _parseDate(dynamic raw) {
    if (raw is Timestamp) {
      final d = raw.toDate();
      return DateTime(d.year, d.month, d.day);
    }
    if (raw is String) {
      final s = raw.trim();
      final d = DateTime.tryParse(s) ?? DateTime.tryParse('${s}T00:00:00');
      if (d != null) return DateTime(d.year, d.month, d.day);
    }
    return DateTime.now();
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      date: _parseDate(json['date']),
      category: json['category']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'amount': amount,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'category': category,
      'notes': notes,
    };
  }

  Expense copyWith({
    String? id,
    String? title,
    double? amount,
    DateTime? date,
    String? category,
    String? notes,
  }) {
    return Expense(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      category: category ?? this.category,
      notes: notes ?? this.notes,
    );
  }
}
