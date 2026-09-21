import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final serverUrl = _serverController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (serverUrl.isEmpty || username.isEmpty || password.isEmpty) return;

    final auth = context.read<AuthController>();
    await auth.login(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // supwave.png is a plain white mark on transparent (the
                  // same source used for the adaptive launcher icon), so
                  // tinting it here keeps it in sync with the app's color
                  // scheme (light/dark, and dynamic color on Android 12+)
                  // instead of a fixed color baked into the asset.
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.primary,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset('assets/supwave.png'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Supwave',
                    textAlign: TextAlign.center,
                    style: theme.typography.emphasized.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to your Navidrome server',
                    textAlign: TextAlign.center,
                    style: theme.typography.baseline.bodyMedium.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  M3ETextField(
                    controller: _serverController,
                    label: 'Server URL',
                    supportingText: 'e.g. music.example.com',
                    leading: const Icon(M3EIcons.dns),
                    keyboardType: TextInputType.url,
                    enabled: !auth.isLoading,
                  ),
                  const SizedBox(height: 16),
                  M3ETextField(
                    controller: _usernameController,
                    label: 'Username',
                    leading: const Icon(M3EIcons.person),
                    enabled: !auth.isLoading,
                  ),
                  const SizedBox(height: 16),
                  M3ETextField(
                    controller: _passwordController,
                    label: 'Password',
                    leading: const Icon(M3EIcons.lock),
                    obscureText: _obscurePassword,
                    enabled: !auth.isLoading,
                    onSubmitted: (_) => _submit(),
                    trailing: M3EIconButton(
                      icon: Icon(
                        _obscurePassword
                            ? M3EIcons.visibility
                            : M3EIcons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      auth.error!,
                      textAlign: TextAlign.center,
                      style: theme.typography.baseline.bodyMedium.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  M3EButton(
                    onPressed: auth.isLoading ? null : _submit,
                    child: auth.isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: M3EProgressIndicator.circular(
                              trackStrokeWidth: 2,
                              color: theme.colorScheme.onPrimary,
                            ),
                          )
                        : const Text('Sign in'),
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
