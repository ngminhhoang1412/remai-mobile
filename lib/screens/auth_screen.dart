import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../router.dart';
import '../state/session.dart';
import '../theme.dart';

enum AuthMode { signIn, signUp }

/// Sign in / Sign up. Errors show inline under the form (wireframes). On success the router's
/// session redirect opens Home.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.mode});

  final AuthMode mode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  bool get _signUp => widget.mode == AuthMode.signUp;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Client-side checks mirror user-auth "Registration input validation"; the server re-checks.
  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) return 'Enter a valid email address.';
    if (_signUp) {
      final name = _name.text.trim();
      if (name.isEmpty) return 'Enter your name.';
      if (name.length > 80) return 'Name must be at most 80 characters.';
      if (_password.text.length < 8) return 'Password must be at least 8 characters.';
      if (_password.text.length > 72) return 'Password must be at most 72 characters.';
    } else if (_password.text.isEmpty) {
      return 'Enter your password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionState>();
    try {
      if (_signUp) {
        await session.signUp(_email.text, _name.text, _password.text);
      } else {
        await session.signIn(_email.text, _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.s5, vertical: Space.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'remai',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                    const SizedBox(height: Space.s1),
                    Text(
                      _signUp ? 'Create your account' : 'Sign in to your notes',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: FontSizes.body, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: Space.s5),
                    TextField(
                      key: const ValueKey('auth-email'),
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.email],
                    ),
                    if (_signUp) ...[
                      const SizedBox(height: Space.s3),
                      TextField(
                        key: const ValueKey('auth-name'),
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        inputFormatters: [LengthLimitingTextInputFormatter(80)],
                      ),
                    ],
                    const SizedBox(height: Space.s3),
                    TextField(
                      key: const ValueKey('auth-password'),
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: _signUp ? 'At least 8 characters' : null,
                      ),
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.s3),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey('auth-error'),
                          style: const TextStyle(color: AppColors.danger, fontSize: FontSizes.small),
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.s4),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_signUp ? 'Sign up' : 'Sign in'),
                    ),
                    const SizedBox(height: Space.s3),
                    TextButton(
                      onPressed: _busy ? null : () => context.go(_signUp ? Routes.signIn : Routes.signUp),
                      child: Text(_signUp ? 'Have an account? Sign in' : 'No account? Sign up'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
