import '../models/expense_model.dart';

abstract class ApiHandler {
  Future<List<Expense>> fetchExpenses();
  Stream<List<Expense>> expensesStream();
  Future<bool> addExpense(Expense expense);
  Future<bool> updateExpense(Expense expense);
  Future<bool> deleteExpense(String id);
  Future<bool> deleteAll();
}