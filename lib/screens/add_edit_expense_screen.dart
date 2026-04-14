import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/expense_model.dart';
import '../services/api_handler.dart';
import '../theme/app_theme.dart';

class AddEditExpenseScreen extends StatefulWidget {
  final ApiHandler apiService;
  final Expense? expense;

  const AddEditExpenseScreen({super.key, required this.apiService, this.expense});

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _notesCtrl;

  bool _isSaving = false;
  DateTime _date = DateTime.now();
  String _category = 'General';

  // ── Animation controllers ──
  late AnimationController _pageCtrl;
  late AnimationController _saveCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;
  late Animation<double> _saveScale;

  static const _categories = [
    'General', 'Grocery', 'Car Repairs', 'Gym Requirements',
    'Entertainment', 'Utilities', 'Healthcare',
  ];

  bool get _isNew => widget.expense == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.expense?.title ?? '');
    _amountCtrl = TextEditingController(
        text: widget.expense != null
            ? widget.expense!.amount.toStringAsFixed(2)
            : '');
    _notesCtrl = TextEditingController(text: widget.expense?.notes ?? '');

    if (!_isNew) {
      _date = widget.expense!.date;
      _category = _categories.contains(widget.expense!.category)
          ? widget.expense!.category
          : 'General';
    }

    // Page entrance animation
    _pageCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _pageFade = CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOut);
    _pageSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pageCtrl, curve: Curves.easeOutCubic));

    // Save button pulse
    _saveCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 160),
        lowerBound: 0.95,
        upperBound: 1.0)
      ..value = 1.0;
    _saveScale = _saveCtrl;

    // Error shake
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    // _shakeAnim drives an offset on the save button (used in build via AnimatedBuilder)

    _pageCtrl.forward();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _saveCtrl.dispose();
    _shakeCtrl.dispose();
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Validators ──
  String? _validateTitle(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Title is required';
    if (t.length < 2) return 'At least 2 characters';
    if (t.length > 80) return 'Max 80 characters';
    return null;
  }

  String? _validateAmount(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Amount is required';
    final n = double.tryParse(t);
    if (n == null) return 'Enter a valid number';
    if (n <= 0) return 'Must be greater than \$0.00';
    if (n > 1000000) return 'Cannot exceed \$1,000,000';
    final parts = t.split('.');
    if (parts.length > 1 && parts[1].length > 2) return 'Max 2 decimal places';
    return null;
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (p != null) setState(() => _date = p);
  }

  Future<void> _save() async {
    HapticFeedback.lightImpact();

    if (!_formKey.currentState!.validate()) {
      // Shake animation on validation fail
      _shakeCtrl.forward(from: 0);
      HapticFeedback.heavyImpact();
      return;
    }
    if (_date.isAfter(DateTime.now())) {
      _showSnack('Date cannot be in the future', error: true);
      return;
    }

    // Button press animation
    await _saveCtrl.reverse();
    await _saveCtrl.forward();

    setState(() => _isSaving = true);

    final expense = Expense(
      id: widget.expense?.id,
      title: _titleCtrl.text.trim(),
      amount: double.parse(_amountCtrl.text.trim()),
      date: _date,
      category: _category,
      notes: _notesCtrl.text.trim(),
    );

    final ok = _isNew
        ? await widget.apiService.addExpense(expense)
        : await widget.apiService.updateExpense(expense);

    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      } else {
        HapticFeedback.heavyImpact();
        _showSnack('Failed to save. Please try again.', error: true);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Delete Expense?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: Text('Remove "${widget.expense!.title}"?\nThis cannot be undone.',
              style: const TextStyle(color: AppTheme.textMid, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      final ok = await widget.apiService.deleteExpense(widget.expense!.id!);
      if (mounted) {
        if (ok) {
          Navigator.pop(context, true);
        } else {
          _showSnack('Could not delete.', error: true);
        }
      }
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isNew ? 'New Expense' : 'Edit Expense'),
        leading: IconButton(
          icon: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: AppTheme.textDark),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isNew)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.error, size: 18),
                ),
                onPressed: _confirmDelete,
              ),
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _pageFade,
        child: SlideTransition(
          position: _pageSlide,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                // ── Category picker — FIX: uses Wrap instead of fixed-height ListView ──
                _SectionLabel(label: 'Category'),
                const SizedBox(height: 10),
                _buildCategoryPicker(),
                const SizedBox(height: 24),

                _SectionLabel(label: 'Title'),
                const SizedBox(height: 8),
                _AnimatedField(
                  child: TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Weekly groceries',
                      prefixIcon: Icon(Icons.edit_outlined,
                          size: 18, color: AppTheme.textMid),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 80,
                    validator: _validateTitle,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ),
                const SizedBox(height: 16),

                _SectionLabel(label: 'Amount'),
                const SizedBox(height: 8),
                _AnimatedField(
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      prefixIcon: Icon(Icons.attach_money_rounded,
                          size: 18, color: AppTheme.textMid),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _validateAmount,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),

                _SectionLabel(label: 'Date'),
                const SizedBox(height: 8),
                _DatePicker(date: _date, onTap: _pickDate),
                const SizedBox(height: 16),

                _SectionLabel(label: 'Notes (optional)'),
                const SizedBox(height: 8),
                _AnimatedField(
                  child: TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Any extra details...',
                      prefixIcon: Icon(Icons.notes_outlined,
                          size: 18, color: AppTheme.textMid),
                      alignLabelWithHint: true,
                    ),
                    maxLength: 200,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Save button with scale animation ──
                ScaleTransition(
                  scale: _saveScale,
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.categoryColors[_category] ??
                            AppTheme.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Icon(Icons.check_rounded, size: 22),
                      label: Text(
                        _isSaving
                            ? 'Saving...'
                            : (_isNew ? 'Add Expense' : 'Save Changes'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── FIX: Category picker uses Wrap — no overflow, no fixed height ──
  Widget _buildCategoryPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((cat) {
        final isSelected = cat == _category;
        final color = AppTheme.categoryColors[cat] ?? AppTheme.primary;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _category = cat);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade200,
                width: 1.5,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_categoryIconFor(cat),
                    color: isSelected ? Colors.white : color, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    cat,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppTheme.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _categoryIconFor(String cat) {
    switch (cat.toLowerCase()) {
      case 'grocery':           return Icons.shopping_cart_outlined;
      case 'car repairs':       return Icons.directions_car_outlined;
      case 'gym requirements':  return Icons.fitness_center_outlined;
      case 'entertainment':     return Icons.movie_outlined;
      case 'utilities':         return Icons.bolt_outlined;
      case 'healthcare':        return Icons.favorite_outline;
      default:                  return Icons.receipt_outlined;
    }
  }
}

// ── Reusable animated field wrapper ──
class _AnimatedField extends StatefulWidget {
  final Widget child;
  const _AnimatedField({required this.child});

  @override
  State<_AnimatedField> createState() => _AnimatedFieldState();
}

class _AnimatedFieldState extends State<_AnimatedField>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
        lowerBound: 0.98,
        upperBound: 1.0)
      ..value = 1.0;
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) {
        if (focused) {
          _ctrl.reverse();
        } else {
          _ctrl.forward();
        }
      },
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Section label ──
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMid),
      );
}

// ── Date picker row ──
class _DatePicker extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  const _DatePicker({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F2FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppTheme.textMid),
            const SizedBox(width: 12),
            Text(
              DateFormat.yMMMd().format(date),
              style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppTheme.textMid),
          ],
        ),
      ),
    );
  }
}
