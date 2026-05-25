import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yamtrack/src/models/library/collected_ownership.dart';
import 'package:yamtrack/src/utils/library_utils.dart';

Future<CollectedOwnershipPick?> showCollectedOwnershipSheet(
  BuildContext context, {
  CollectedOwnershipVariant? current,
  String? currentPrice,
}) {
  return showModalBottomSheet<CollectedOwnershipPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    builder: (context) => _CollectedOwnershipSheet(
      current: current,
      currentPrice: currentPrice,
    ),
  );
}

class _CollectedOwnershipSheet extends StatefulWidget {
  const _CollectedOwnershipSheet({
    this.current,
    this.currentPrice,
  });

  final CollectedOwnershipVariant? current;
  final String? currentPrice;

  @override
  State<_CollectedOwnershipSheet> createState() => _CollectedOwnershipSheetState();
}

class _CollectedOwnershipSheetState extends State<_CollectedOwnershipSheet> {
  CollectedOwnershipVariant? _selected;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _priceController = TextEditingController(text: widget.currentPrice ?? '');
  }

  @override
  void dispose() {
    scheduleTextEditingControllerDispose(_priceController);
    super.dispose();
  }

  void _submit() {
    final variant = _selected;
    if (variant == null) {
      return;
    }
    final price = _priceController.text.trim();
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(
      CollectedOwnershipPick(
        variant: variant,
        price: price.isEmpty ? null : price,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ownership',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'How do you own this title, and what did you pay?',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final variant in CollectedOwnershipVariant.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: _selected == variant
                      ? scheme.primaryContainer.withValues(alpha: 0.55)
                      : scheme.surfaceContainerHigh,
                  leading: Icon(
                    variant.icon,
                    color: _selected == variant ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                  title: Text(variant.sheetLabel),
                  trailing: _selected == variant
                      ? Icon(Icons.check, color: scheme.primary)
                      : null,
                  onTap: () => setState(() => _selected = variant),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Price paid',
                hintText: 'e.g. 24.90',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _selected == null ? null : _submit,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
