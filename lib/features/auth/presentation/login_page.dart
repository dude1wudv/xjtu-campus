import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/core_providers.dart';
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
  final _captchaController = TextEditingController();
  final _mfaController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  String? _accountLabel;
  bool _webVpn = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final session = ref.read(campusSessionProvider);
      await session.restore();
      if (mounted) setState(() => _webVpn = session.useWebVpn);
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    _mfaController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool demo}) async {
    if (demo) {
      final id = _idController.text.trim().isEmpty
          ? 'demo'
          : _idController.text;
      final password = _passwordController.text.isEmpty
          ? 'demo'
          : _passwordController.text;
      final ok = await ref
          .read(authControllerProvider.notifier)
          .login(studentId: id, password: password, demo: true);
      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.loginDemoSuccess)));
        context.go('/home');
      }
      return;
    }

    final auth = ref.read(authControllerProvider);
    final extraStep =
        auth.awaitingCaptcha || auth.awaitingMfa || auth.awaitingAccountChoice;
    if (!extraStep && !_formKey.currentState!.validate()) return;

    final ok = await ref.read(authControllerProvider.notifier).login(
      studentId: _idController.text,
      password: _passwordController.text,
      captcha: _captchaController.text,
      mfaCode: _mfaController.text,
      accountLabel: _accountLabel,
    );
    if (!mounted) return;
    if (ok) {
      _passwordController.clear();
      _captchaController.clear();
      _mfaController.clear();
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
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStrings.webVpnLabel),
            subtitle: const Text(AppStrings.webVpnHint),
            value: _webVpn,
            onChanged: auth.busy
                ? null
                : (v) async {
                    setState(() => _webVpn = v);
                    await ref.read(campusSessionProvider).setUseWebVpn(v);
                  },
          ),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _idController,
                  keyboardType: TextInputType.visiblePassword,
                  autofillHints: const [AutofillHints.username],
                  enabled: !auth.awaitingCaptcha &&
                      !auth.awaitingMfa &&
                      !auth.awaitingAccountChoice,
                  decoration: const InputDecoration(
                    labelText: AppStrings.studentIdLabel,
                    hintText: AppStrings.studentIdHint,
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? AppStrings.loginRequired
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  enabled: !auth.awaitingCaptcha &&
                      !auth.awaitingMfa &&
                      !auth.awaitingAccountChoice,
                  decoration: InputDecoration(
                    labelText: AppStrings.passwordLabel,
                    hintText: AppStrings.passwordHint,
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? AppStrings.showPassword
                          : AppStrings.hidePassword,
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      (value == null || value.isEmpty)
                      ? AppStrings.passwordRequired
                      : null,
                ),
              ],
            ),
          ),
          if (auth.awaitingCaptcha) ...[
            const SizedBox(height: 16),
            const Text(AppStrings.captchaLead),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: auth.captchaImage == null
                      ? const SizedBox(
                          height: 48,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            auth.captchaImage!,
                            height: 48,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: AppStrings.refreshCaptcha,
                  onPressed: auth.busy
                      ? null
                      : () => ref
                            .read(authControllerProvider.notifier)
                            .refreshCaptcha(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _captchaController,
              decoration: const InputDecoration(
                labelText: AppStrings.captchaLabel,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(demo: false),
            ),
          ],
          if (auth.awaitingMfa) ...[
            const SizedBox(height: 16),
            Text(
              auth.maskedPhone == null
                  ? AppStrings.mfaLead
                  : '${AppStrings.mfaLead}\n${AppStrings.mfaPhonePrefix}${auth.maskedPhone}',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mfaController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: AppStrings.mfaCodeLabel,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: auth.busy
                    ? null
                    : () =>
                          ref.read(authControllerProvider.notifier).sendMfaSms(),
                child: const Text(AppStrings.resendMfa),
              ),
            ),
          ],
          if (auth.awaitingAccountChoice) ...[
            const SizedBox(height: 16),
            const Text(AppStrings.accountChoiceLead),
            const SizedBox(height: 8),
            for (final choice in auth.accountChoices)
              ListTile(
                title: Text(choice.name),
                leading: Icon(
                  _accountLabel == choice.label
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.navy,
                ),
                onTap: () => setState(() => _accountLabel = choice.label),
              ),
          ],
          if (auth.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              auth.errorMessage!,
              style: const TextStyle(color: AppColors.alert),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: auth.busy
                ? null
                : () {
                    final id = _idController.text.trim();
                    if (id.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(AppStrings.loginRequired)),
                      );
                      return;
                    }
                    context.push(
                      '/login/web?studentId=${Uri.encodeComponent(id)}',
                    );
                  },
            child: const Text(AppStrings.webLoginAction),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: auth.busy ? null : () => _submit(demo: false),
            child: auth.busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(AppStrings.loginAction),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: auth.busy ? null : () => _submit(demo: true),
            child: const Text(AppStrings.loginDemo),
          ),
          if (auth.isLoggedIn) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).logout(),
              child: const Text(AppStrings.logoutAction),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(AppStrings.loginPrivacy, style: TextStyle(height: 1.45)),
          ),
        ],
      ),
    );
  }
}
