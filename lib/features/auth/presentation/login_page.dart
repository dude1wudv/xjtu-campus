import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final password = _passwordController.text;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(studentId: _idController.text, password: password);
    _passwordController.clear();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(AppStrings.loginSuccess)));
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.loginTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(AppStrings.loginHint),
          const SizedBox(height: 8),
          Text(
            AppStrings.casAdapterNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _idController,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    labelText: AppStrings.studentIdLabel,
                    hintText: AppStrings.studentIdHint,
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                      ? AppStrings.loginRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(
                    labelText: AppStrings.passwordLabel,
                    hintText: AppStrings.passwordHint,
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty)
                      ? AppStrings.passwordRequired
                      : null,
                ),
              ],
            ),
          ),
          if (auth.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              auth.errorMessage!,
              style: const TextStyle(color: AppColors.alert),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: auth.busy ? null : _submit,
            child: auth.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(AppStrings.loginAction),
          ),
          if (auth.isLoggedIn) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              child: const Text(AppStrings.logoutAction),
            ),
          ],
        ],
      ),
    );
  }
}
