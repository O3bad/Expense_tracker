import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_db.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {

  // ── State ──
  bool _isLogin = true;
  bool _obscurePw  = true;
  bool _obscureCpw = true;
  bool _loading    = false;

  final _emailCtrl   = TextEditingController();
  final _pwCtrl      = TextEditingController();
  final _confirmCtrl = TextEditingController();

  String? _emailErr;
  String? _pwErr;
  String? _confirmErr;
  String? _generalErr;

  late AnimationController _animCtrl;
  late Animation<double>  _fadeAnim;
  late Animation<Offset>  _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06), end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _checkEmail(String v) {
    if (v.trim().isEmpty) return 'Email is required';
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$').hasMatch(v.trim())) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _checkPassword(String v) {
    if (v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'At least 8 characters required';
    if (!_isLogin && !RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Include at least one uppercase letter';
    }
    if (!_isLogin && !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Include at least one number';
    }
    return null;
  }

  String? _checkConfirm(String v) {
    if (v.isEmpty) return 'Please confirm your password';
    if (v != _pwCtrl.text) return 'Passwords do not match';
    return null;
  }

  bool _validate() {
    final e = _checkEmail(_emailCtrl.text);
    final p = _checkPassword(_pwCtrl.text);
    final c = !_isLogin ? _checkConfirm(_confirmCtrl.text) : null;
    setState(() {
      _emailErr = e; _pwErr = p; _confirmErr = c; _generalErr = null;
    });
    return e == null && p == null && c == null;
  }

  String _firebaseMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':         return 'No account found with this email.';
      case 'wrong-password':         return 'Incorrect password. Please try again.';
      case 'invalid-credential':     return 'Email or password is incorrect.';
      case 'email-already-in-use':   return 'An account with this email already exists.';
      case 'invalid-email':          return 'The email address is not valid.';
      case 'weak-password':          return 'Password is too weak. Try a stronger one.';
      case 'too-many-requests':      return 'Too many attempts. Please wait and try again.';
      case 'network-request-failed': return 'Network error. Check your connection.';
      case 'user-disabled':          return 'This account has been disabled.';
      default:                       return 'Something went wrong (${e.code}).';
    }
  }


  Future<void> _signIn() async {
    setState(() { _loading = true; _generalErr = null; });
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      // FIX: Ensure user document exists (covers users who registered before this fix).
      if (credential.user != null) {
        await FirestoreDb().createUserDocument(credential.user!);
      }
      // AuthGate stream picks up the new user automatically — no manual navigate needed.
      if (mounted) setState(() { _loading = false; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _loading = false; _generalErr = _firebaseMsg(e); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _generalErr = 'An unexpected error occurred.'; });
    }
  }


  Future<void> _signUp() async {
    setState(() { _loading = true; _generalErr = null; });
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      // FIX: Create the user document in Firestore immediately after sign-up.
      // Without this, the users/{uid} parent document never exists, so the
      // expenses subcollection writes are silently dropped by Firestore.
      if (credential.user != null) {
        await FirestoreDb().createUserDocument(credential.user!);
      }
      // AuthGate stream picks up the new user automatically.
      if (mounted) setState(() { _loading = false; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() { _loading = false; _generalErr = _firebaseMsg(e); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _generalErr = 'An unexpected error occurred.'; });
    }
  }


  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _emailErr = 'Enter your email first';
      });
      return;
    }
    if (_checkEmail(email) != null) {
      setState(() {
        _emailErr = 'Enter a valid email address';
      });
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Password reset email sent!'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _generalErr = _firebaseMsg(e);
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    if (_isLogin) {
      await _signIn();
    } else {
      await _signUp();
    }
  }

  void _toggleMode() {
    _animCtrl.reset();
    setState(() {
      _isLogin = !_isLogin;
      _emailErr = _pwErr = _confirmErr = _generalErr = null;
      _loading = false;
    });
    _animCtrl.forward();
  }


  int _pwStrength(String p) {
    int s = 0;
    if (p.length >= 6) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#$%^&*]').hasMatch(p)) s++;
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6C63FF), Color(0xFF9C27B0), Color(0xFF3F51B5)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                child: Column(
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 20, offset: const Offset(0, 6))],
                      ),
                      child: const Icon(Icons.account_balance_wallet_rounded,
                          size: 34, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _isLogin ? 'Welcome back 👋' : 'Create account',
                        key: ValueKey(_isLogin),
                        style: const TextStyle(
                          color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.w800, letterSpacing: -0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _isLogin
                            ? 'Sign in to track your expenses'
                            : 'Start managing your money today',
                        key: ValueKey('sub$_isLogin'),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [

                            _field(
                              ctrl: _emailCtrl,
                              label: 'Email address',
                              icon: Icons.email_outlined,
                              keyboard: TextInputType.emailAddress,
                              error: _emailErr,
                              onChanged: (_) {
                                setState(() {
                                  _emailErr = null;
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            _field(
                              ctrl: _pwCtrl,
                              label: 'Password',
                              icon: Icons.lock_outline,
                              obscure: _obscurePw,
                              error: _pwErr,
                              onChanged: (_) {
                                setState(() {
                                  _pwErr = null;
                                });
                              },
                              toggleObscure: () {
                                setState(() {
                                  _obscurePw = !_obscurePw;
                                });
                              },
                            ),

                            if (!_isLogin && _pwCtrl.text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _strengthBar(_pwCtrl.text),
                            ],
                            const SizedBox(height: 16),

                            if (!_isLogin) ...[
                              _field(
                                ctrl: _confirmCtrl,
                                label: 'Confirm password',
                                icon: Icons.lock_outline,
                                obscure: _obscureCpw,
                                error: _confirmErr,
                                onChanged: (_) {
                                  setState(() {
                                    _confirmErr = null;
                                  });
                                },
                                toggleObscure: () {
                                  setState(() {
                                    _obscureCpw = !_obscureCpw;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_isLogin)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _forgotPassword,
                                  style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.primary),
                                  child: const Text('Forgot password?',
                                      style: TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),

                            if (_generalErr != null) ...[
                              const SizedBox(height: 4),
                              _errorBanner(_generalErr!),
                              const SizedBox(height: 12),
                            ],

                            const SizedBox(height: 4),

                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(
                                        width: 22, height: 22,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5))
                                    : Text(_isLogin ? 'Sign In' : 'Create Account'),
                              ),
                            ),
                            const SizedBox(height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _isLogin
                                      ? "Don't have an account?  "
                                      : 'Already have an account?  ',
                                  style: const TextStyle(
                                      color: AppTheme.textMid, fontSize: 14),
                                ),
                                GestureDetector(
                                  onTap: _toggleMode,
                                  child: Text(
                                    _isLogin ? 'Sign Up' : 'Sign In',
                                    style: const TextStyle(
                                      color: AppTheme.primary, fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            if (!_isLogin) ...[
                              const SizedBox(height: 14),
                              Center(
                                child: Text(
                                  'Password: 8+ chars, uppercase & number',
                                  style: TextStyle(
                                      color: AppTheme.textMid.withValues(alpha: 0.65),
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
    String? error,
    void Function(String)? onChanged,
    VoidCallback? toggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboard,
          onChanged: onChanged,
          style: const TextStyle(color: AppTheme.textDark, fontSize: 15),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon,
                color: error != null ? AppTheme.error : AppTheme.textMid,
                size: 20),
            suffixIcon: toggleObscure != null
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: AppTheme.textMid, size: 20,
                    ),
                    onPressed: toggleObscure,
                  )
                : null,
            fillColor: error != null
                ? AppTheme.error.withValues(alpha: 0.05)
                : const Color(0xFFF3F2FF),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: error != null
                  ? const BorderSide(color: AppTheme.error, width: 1.5)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: error != null ? AppTheme.error : AppTheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 14),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppTheme.error, size: 14),
                const SizedBox(width: 4),
                Text(error,
                    style: const TextStyle(color: AppTheme.error, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _strengthBar(String pw) {
    final s   = _pwStrength(pw);
    final idx = (s - 1).clamp(0, 3);
    const labels = ['Weak', 'Fair', 'Good', 'Strong'];
    const colors = [AppTheme.error, AppTheme.warning, Color(0xFF8BC34A), AppTheme.success];

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i <= idx ? colors[idx] : Colors.grey.shade200,
                ),
              ),
            )),
          ),
        ),
        const SizedBox(width: 10),
        Text(labels[idx],
            style: TextStyle(
                fontSize: 12, color: colors[idx], fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _errorBanner(String msg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppTheme.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: AppTheme.error, fontSize: 13)),
        ),
      ],
    ),
  );
}
