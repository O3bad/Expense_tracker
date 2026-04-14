import 'dart:ui';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../auth/auth_gate.dart';
import '../models/expense_model.dart';
import '../services/api_handler.dart';
import '../services/firestore_db.dart';
import '../theme/app_theme.dart';
import 'add_edit_expense_screen.dart';

// ── Currency formatter ──────────────────────────────────────────────────────
final _currencyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
String _fmt(double v) => _currencyFmt.format(v);

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with TickerProviderStateMixin {
  final FirestoreDb _db = FirestoreDb();
  ApiHandler get _api => _db;

  String _filterCategory = 'All';
  String _displayName = '';
  String _searchQuery = '';
  int _streamRetryKey = 0;
  bool _insightsMode = false;
  double? _monthlyBudget;

  late AnimationController _fabCtrl;
  late Animation<double> _fabScale;

  static const List<String> _categories = [
    'All', 'General', 'Grocery', 'Car Repairs',
    'Gym Requirements', 'Entertainment', 'Utilities', 'Healthcare',
  ];

  @override
  void initState() {
    super.initState();

    _fabCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
        lowerBound: 0.0,
        upperBound: 1.0);
    _fabScale = CurvedAnimation(parent: _fabCtrl, curve: Curves.elasticOut);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _fabCtrl.forward();
    });

    _loadDisplayName();
    _loadBudget();
  }

  Future<void> _loadDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = await _db.getUserDisplayName(user);
    if (mounted) setState(() => _displayName = name);
  }

  Future<void> _loadBudget() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final b = await _db.getMonthlyBudget(user);
    if (mounted) setState(() => _monthlyBudget = b);
  }

  Future<void> _exportCsv(List<Expense> expenses) async {
    if (expenses.isEmpty) {
      _showSnack('No expenses to export', color: AppTheme.warning);
      return;
    }
    final rows = <List<String>>[
      ['Title', 'Amount', 'Date', 'Category', 'Notes'],
      ...expenses.map((e) => [
            e.title,
            e.amount.toStringAsFixed(2),
            DateFormat('yyyy-MM-dd').format(e.date),
            e.category,
            e.notes.replaceAll('\n', ' '),
          ]),
    ];
    final csvText = csv.encode(rows);
    await SharePlus.instance.share(
      ShareParams(text: csvText, subject: 'Spendly expenses'),
    );
  }

  Future<void> _showBudgetDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final c = TextEditingController(
      text: _monthlyBudget != null && _monthlyBudget! > 0
          ? _monthlyBudget!.toStringAsFixed(0)
          : '',
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Monthly budget',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: 'e.g. 800',
              prefixText: '\$ ',
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                await _db.setMonthlyBudget(user, null);
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadBudget();
              },
              child: const Text('Clear')),
            ElevatedButton(
              onPressed: () async {
                final v = double.tryParse(c.text.trim());
                if (v != null && v > 0) {
                  await _db.setMonthlyBudget(user, v);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await _loadBudget();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
  }

  @override
  void dispose() {
    _fabCtrl.dispose();
    super.dispose();
  }

  IconData _categoryIcon(String cat) {
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

  Color _categoryColor(String cat) =>
      AppTheme.categoryColors[cat] ?? AppTheme.primary;

  Future<void> _delete(String? id) async {
    if (id == null) return;
    final ok = await _api.deleteExpense(id);
    if (ok && mounted) {
      HapticFeedback.mediumImpact();
      _showSnack('Expense deleted',
          icon: Icons.check_circle_outline, color: AppTheme.success);
    }
  }

  void _navigate([Expense? expense]) async {
    if (expense == null) {
      _fabCtrl.reverse();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (ctx, anim, sec) =>
            AddEditExpenseScreen(apiService: _api, expense: expense),
        transitionsBuilder: (ctx, anim, sec, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, 1), end: Offset.zero)
                .animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
    if (mounted) _fabCtrl.forward();
    // StreamBuilder auto-updates — no manual _refresh() needed
  }

  void _showSnack(String msg, {IconData? icon, Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
        ],
        Text(msg),
      ]),
      backgroundColor: color ?? AppTheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Clear all expenses?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: const Text('This will permanently remove all items.',
              style: TextStyle(color: AppTheme.textMid, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await _api.deleteAll();
                if (mounted) {
                  _showSnack(
                    ok ? 'All expenses deleted' : 'Failed to delete expenses',
                    icon: ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: ok ? AppTheme.success : AppTheme.error,
                  );
                }
              },
              child: const Text('Delete All'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Sign out?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          content: const Text('You will be returned to the login screen.',
              style: TextStyle(color: AppTheme.textMid, height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 400),
                      pageBuilder: (ctx, anim, sec) => const AuthGate(),
                      transitionsBuilder: (ctx, anim, sec, child) =>
                          FadeTransition(opacity: anim, child: child),
                    ),
                  );
                }
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  List<Expense> _thisMonth(List<Expense> all) {
    final now = DateTime.now();
    return all
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: StreamBuilder<List<Expense>>(
        key: ValueKey(_streamRetryKey),
        stream: _api.expensesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _loadingView();
          }
          if (snapshot.hasError) {
            return _errorView(snapshot.error);
          }

          final allExpenses = snapshot.data ?? [];
          final filtered = _filterCategory == 'All'
              ? allExpenses
              : allExpenses
                  .where((e) => e.category == _filterCategory)
                  .toList();
          final q = _searchQuery.trim().toLowerCase();
          final visible = q.isEmpty
              ? filtered
              : filtered
                  .where((e) =>
                      e.title.toLowerCase().contains(q) ||
                      e.notes.toLowerCase().contains(q))
                  .toList();

          final thisMonthExpenses = _thisMonth(allExpenses);
          final thisMonthTotal =
              thisMonthExpenses.fold(0.0, (s, e) => s + e.amount);
          final filteredTotal = visible.fold(0.0, (s, e) => s + e.amount);

          if (_insightsMode) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppTheme.primary,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top,
                    left: 4,
                    right: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() => _insightsMode = false);
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'Insights',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    children: [
                      Text(
                        'This month — ${_fmt(thisMonthTotal)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _MonthlyCategoryChart(expenses: thisMonthExpenses),
                    ],
                  ),
                ),
              ],
            );
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Hero header ──
              SliverAppBar(
                expandedHeight: 210,
                floating: false,
                pinned: true,
                stretch: true,
                backgroundColor: AppTheme.primary,
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground,
                  ],
                  background: _HeaderBackground(
                    displayName: _displayName.isNotEmpty
                        ? _displayName
                        : (FirebaseAuth.instance.currentUser
                                ?.email
                                ?.split('@')
                                .first ??
                            'there'),
                    thisMonthTotal: thisMonthTotal,
                    thisMonthCount: thisMonthExpenses.length,
                    monthlyBudget: _monthlyBudget,
                    onBudgetTap: _showBudgetDialog,
                  ),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(50),
                  child: Container(
                    color: AppTheme.primary,
                    height: 50,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _categories.length,
                      itemBuilder: (_, i) {
                        final cat = _categories[i];
                        final isSelected = cat == _filterCategory;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _filterCategory = cat);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSelected
                                    ? AppTheme.primary
                                    : Colors.white,
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                actions: [
                  _appBarBtn(Icons.insights_outlined, () {
                    HapticFeedback.lightImpact();
                    setState(() => _insightsMode = true);
                  }),
                  _appBarBtn(
                      Icons.share_rounded, () => _exportCsv(allExpenses)),
                  _appBarBtn(Icons.delete_sweep_outlined, _showDeleteAllDialog),
                  const SizedBox(width: 6),
                  _appBarBtn(Icons.logout_rounded, _showLogoutDialog),
                  const SizedBox(width: 8),
                ],
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search title or notes…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 22),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Body states ──
              if (visible.isEmpty)
                SliverFillRemaining(
                  child: _emptyState(
                    Icons.receipt_long_outlined,
                    'No expenses yet',
                    _filterCategory == 'All' && _searchQuery.trim().isEmpty
                        ? 'Tap + to add your first expense.'
                        : 'No matching expenses.',
                  ),
                )
              else ...[
                if (_filterCategory != 'All' || _searchQuery.trim().isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _searchQuery.trim().isNotEmpty
                                  ? 'Search results'
                                  : _filterCategory,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppTheme.textDark),
                            ),
                          ),
                          Text(
                              _fmt(filteredTotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: AppTheme.primary)),
                        ],
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _AnimatedExpenseCard(
                        key: Key(visible[i].id ?? '$i'),
                        item: visible[i],
                        index: i,
                        onTap: () => _navigate(visible[i]),
                        onDelete: () => _delete(visible[i].id),
                        categoryColor: _categoryColor(visible[i].category),
                        categoryIcon: _categoryIcon(visible[i].category),
                      ),
                      childCount: visible.length,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScale,
        child: FloatingActionButton.extended(
          onPressed: () => _navigate(),
          backgroundColor: AppTheme.primary,
          elevation: 6,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text('Add Expense',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }

  Widget _loadingView() {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary)),
    );
  }

  Widget _errorView(Object? error) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: _emptyState(
        Icons.wifi_off_outlined,
        'Could not load expenses',
        'Check your internet connection and try again.',
        actionLabel: 'Retry',
        onAction: () => setState(() => _streamRetryKey++),
      ),
    );
  }

  Widget _appBarBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle,
      {String? actionLabel, VoidCallback? onAction}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 38,
                    color: AppTheme.primary.withValues(alpha: 0.4)),
              ),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textMid, fontSize: 14)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Animated expense card that slides in staggered ──────────────────────────
class _AnimatedExpenseCard extends StatefulWidget {
  final Expense item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final Color categoryColor;
  final IconData categoryIcon;

  const _AnimatedExpenseCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    required this.onDelete,
    required this.categoryColor,
    required this.categoryIcon,
  });

  @override
  State<_AnimatedExpenseCard> createState() => _AnimatedExpenseCardState();
}

class _AnimatedExpenseCardState extends State<_AnimatedExpenseCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    final delay =
        Duration(milliseconds: (widget.index.clamp(0, 6) * 60));
    Future.delayed(delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Dismissible(
          key: Key(widget.item.id ?? '${widget.index}'),
          direction: DismissDirection.endToStart,
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AppTheme.error,
                borderRadius: BorderRadius.circular(18)),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: 24),
                SizedBox(height: 4),
                Text('Delete',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          confirmDismiss: (_) async {
            HapticFeedback.mediumImpact();
            return true;
          },
          onDismissed: (_) => widget.onDelete(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.categoryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.categoryIcon,
                        color: widget.categoryColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppTheme.textDark),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: widget.categoryColor
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.item.category,
                                style: TextStyle(
                                    color: widget.categoryColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                DateFormat.yMMMd().format(widget.item.date),
                                style: const TextStyle(
                                    color: AppTheme.textMid, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (widget.item.notes.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.item.notes,
                            style: TextStyle(
                                color:
                                    AppTheme.textMid.withValues(alpha: 0.7),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ── Formatted with thousands separators ──────────────
                  Text(
                    _fmt(widget.item.amount),
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: widget.categoryColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── This month spending by category (bar chart) ─────────────────────────────
class _MonthlyCategoryChart extends StatelessWidget {
  final List<Expense> expenses;

  const _MonthlyCategoryChart({required this.expenses});

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Text(
          'No expenses this month yet.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 15,
          ),
        ),
      );
    }
    final sums = <String, double>{};
    for (final e in expenses) {
      sums[e.category] = (sums[e.category] ?? 0) + e.amount;
    }
    final sorted = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxY = (sorted.first.value * 1.15).clamp(1.0, double.infinity);

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, m) => Text(
                  v >= 1000
                      ? '\$${(v / 1000).toStringAsFixed(1)}k'
                      : '\$${v.toInt()}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  final label = sorted[i].key;
                  final short =
                      label.length > 7 ? '${label.substring(0, 6)}…' : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      short,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(sorted.length, (i) {
            final color =
                AppTheme.categoryColors[sorted[i].key] ?? AppTheme.primary;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: sorted[i].value,
                  color: color,
                  width: 16,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ── Header background widget ──────────────────────────────────────────────
class _HeaderBackground extends StatelessWidget {
  final String displayName;
  final double thisMonthTotal;
  final int thisMonthCount;
  final double? monthlyBudget;
  final VoidCallback onBudgetTap;

  const _HeaderBackground({
    required this.displayName,
    required this.thisMonthTotal,
    required this.thisMonthCount,
    required this.onBudgetTap,
    this.monthlyBudget,
  });

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, $displayName 👋',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'My Expenses',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onBudgetTap,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('This Month',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.75),
                                        fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(
                                  _fmt(thisMonthTotal),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '$thisMonthCount item${thisMonthCount != 1 ? 's' : ''}',
                                  style: TextStyle(
                                      color: Colors.white
                                          .withValues(alpha: 0.75),
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(monthLabel,
                                      style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.9),
                                          fontSize: 11)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (monthlyBudget != null && monthlyBudget! > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${_fmt(thisMonthTotal)} of ${_fmt(monthlyBudget!)} budget',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (thisMonthTotal / monthlyBudget!)
                                  .clamp(0.0, 1.0),
                              minHeight: 8,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                thisMonthTotal > monthlyBudget!
                                    ? AppTheme.error
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          Text(
                            'Tap to set a monthly budget',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
