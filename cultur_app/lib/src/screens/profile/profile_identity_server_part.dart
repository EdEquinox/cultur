part of 'profile_page.dart';

class _ProfileUserCard extends StatelessWidget {
  const _ProfileUserCard({required this.session, required this.theme});

  final AuthSession? session;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                ((session?.displayName ?? session?.username ?? 'U').trim())
                    .characters
                    .first
                    .toUpperCase(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session?.displayName ?? session?.username ?? 'cult.u.r user',
                    style: CulturCatalogTypography.profileTitle(theme),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session?.username ?? '',
                    style: CulturCatalogTypography.profileSubtitle(theme, theme.colorScheme),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAndroidInstallCard extends StatelessWidget {
  const _ProfileAndroidInstallCard({required this.theme});

  final ThemeData theme;

  Future<void> _openApk(BuildContext context) async {
    final uri = Uri.tryParse(AppBuildConfig.androidApkUrl.trim());
    if (uri == null) {
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the download link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.android, color: scheme.primary),
        title: Text(
          'Install Android app',
          style: CulturCatalogTypography.listTitle(theme),
        ),
        subtitle: Text(
          'Download the APK for your phone',
          style: CulturCatalogTypography.listMeta(theme, scheme),
        ),
        trailing: const Icon(Icons.download_outlined),
        onTap: () => _openApk(context),
      ),
    );
  }
}

class _ProfileServerCard extends StatelessWidget {
  const _ProfileServerCard({required this.serverUrl, required this.theme});

  final String? serverUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server', style: CulturCatalogTypography.sectionHeading(theme)),
            const SizedBox(height: 8),
            Text(
              serverUrl ?? 'No server configured',
              style: CulturCatalogTypography.bodyText(theme, theme.colorScheme),
            ),
          ],
        ),
      ),
    );
  }
}
