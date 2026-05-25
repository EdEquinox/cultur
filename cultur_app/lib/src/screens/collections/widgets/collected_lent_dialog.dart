import 'package:flutter/material.dart';

/// Result of marking a collected title as lent.
class CollectedLentSubmit {
  const CollectedLentSubmit({
    required this.borrowerName,
    required this.lentAtUtc,
  });

  final String borrowerName;
  final DateTime lentAtUtc;
}

enum _LentWhenOption { now, custom }

/// Prompts for borrower and loan date when marking a collected title as lent.
Future<CollectedLentSubmit?> showCollectedLentDialog(BuildContext context) async {
  return showModalBottomSheet<CollectedLentSubmit>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (sheetContext) => const _CollectedLentSheet(),
  );
}

class _CollectedLentSheet extends StatefulWidget {
  const _CollectedLentSheet();

  @override
  State<_CollectedLentSheet> createState() => _CollectedLentSheetState();
}

class _CollectedLentSheetState extends State<_CollectedLentSheet> {
  late final TextEditingController _nameController;
  _LentWhenOption _when = _LentWhenOption.now;
  late DateTime _customLocal;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _customLocal = DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  DateTime get _lentAtUtc {
    return switch (_when) {
      _LentWhenOption.now => DateTime.now().toUtc(),
      _LentWhenOption.custom => DateTime(
        _customLocal.year,
        _customLocal.month,
        _customLocal.day,
        _customLocal.hour,
        _customLocal.minute,
      ).toUtc(),
    };
  }

  Future<void> _pickDate() async {
    if (_when != _LentWhenOption.custom) {
      setState(() {
        _when = _LentWhenOption.custom;
        _customLocal = DateTime.now();
      });
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customLocal = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _customLocal.hour,
        _customLocal.minute,
      );
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      CollectedLentSubmit(
        borrowerName: name,
        lentAtUtc: _lentAtUtc,
      ),
    );
  }

  Widget _whenTile({
    required String title,
    required _LentWhenOption value,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _when == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap ?? () => setState(() => _when = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(title)),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = MaterialLocalizations.of(context);
    final customDateLabel = loc.formatMediumDate(
      DateTime(_customLocal.year, _customLocal.month, _customLocal.day),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Mark as lent',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Borrower name',
                  hintText: 'Who borrowed this?',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              Text(
                'Loan date',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              _whenTile(title: 'Today', value: _LentWhenOption.now),
              _whenTile(
                title: customDateLabel,
                value: _LentWhenOption.custom,
                onTap: _pickDate,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
