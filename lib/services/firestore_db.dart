import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'api_handler.dart';
import '../models/expense_model.dart';

class FirestoreDb implements ApiHandler {
  static const _usersCollection = "users";
  static const _expensesCollection = "expenses";

  CollectionReference<Map<String, dynamic>> get _collection {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No authenticated user.');
    return FirebaseFirestore.instance
        .collection(_usersCollection)
        .doc(user.uid)
        .collection(_expensesCollection);
  }

  Future<void> createUserDocument(User user) async {
    final docRef = FirebaseFirestore.instance
        .collection(_usersCollection)
        .doc(user.uid);

    final snap = await docRef.get();

    if (!snap.exists) {
      final name = (user.displayName?.isNotEmpty == true)
          ? user.displayName!
          : (user.email?.split('@').first ?? 'user');

      await docRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<double?> getMonthlyBudget(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(user.uid)
          .get();
      final v = doc.data()?['monthlyBudget'];
      if (v is num && v > 0) return v.toDouble();
    } catch (e) {
      debugPrint('getMonthlyBudget error: $e');
    }
    return null;
  }

  Future<void> setMonthlyBudget(User user, double? budget) async {
    final ref = FirebaseFirestore.instance
        .collection(_usersCollection)
        .doc(user.uid);
    if (budget == null || budget <= 0) {
      await ref.set(
        {'monthlyBudget': FieldValue.delete()},
        SetOptions(merge: true),
      );
    } else {
      await ref.set(
        {'monthlyBudget': budget},
        SetOptions(merge: true),
      );
    }
  }

  /// Fetches the user's display name from Firestore.
  /// Falls back to email prefix if not found.
  Future<String> getUserDisplayName(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_usersCollection)
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final name = doc.data()?['name']?.toString() ?? '';
        if (name.isNotEmpty) return name;
      }
    } catch (e) {
      debugPrint('getUserDisplayName error: $e');
    }
    return user.email?.split('@').first ?? 'there';
  }

  @override
  Future<List<Expense>> fetchExpenses() async {
    // Do NOT catch silently — let the error propagate so the UI can
    // distinguish "empty" from "network/firebase failure".
    final snap = await _collection.orderBy('date', descending: true).get();
    return snap.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return Expense.fromJson(data);
    }).toList();
  }

  @override
  Future<bool> addExpense(Expense expense) async {
    try {
      await _collection.add(expense.toJson());
      return true;
    } catch (e) {
      debugPrint('addExpense error: $e');
      return false;
    }
  }

  @override
  Future<bool> updateExpense(Expense expense) async {
    if (expense.id == null || expense.id!.isEmpty) return false;
    try {
      await _collection.doc(expense.id).set(expense.toJson());
      return true;
    } catch (e) {
      debugPrint('updateExpense error: $e');
      return false;
    }
  }

  @override
  Future<bool> deleteExpense(String id) async {
    if (id.isEmpty) return false;
    try {
      await _collection.doc(id).delete();
      return true;
    } catch (e) {
      debugPrint('deleteExpense error: $e');
      return false;
    }
  }

  @override
  Stream<List<Expense>> expensesStream() {
    return _collection
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['id'] = doc.id;
              return Expense.fromJson(data);
            }).toList());
  }

  @override
  Future<bool> deleteAll() async {
    try {
      final snap = await _collection.get();
      if (snap.docs.isEmpty) return true;
      const chunkSize = 400;
      final docs = snap.docs;
      for (int i = 0; i < docs.length; i += chunkSize) {
        final chunk = docs.skip(i).take(chunkSize);
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      return true;
    } catch (e) {
      debugPrint('deleteAll error: $e');
      return false;
    }
  }
}
