import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamtrack/src/providers/library_search_focus_provider.dart';

/// Horizontal inset used with library search fields (aligns with list content).
const double librarySearchHorizontalInset = 12;

/// Live filter field for in-memory library / list screens.
class LibraryItemSearchField extends ConsumerStatefulWidget {
  const LibraryItemSearchField({
    required this.controller,
    required this.onChanged,
    super.key,
    this.hintText = 'Search titles…',
    this.onSubmitted,
    this.trailing,
    this.focusNode,
    this.registerForPageSearchFab = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final FocusNode? focusNode;

  /// When true, the floating search FAB can focus this field on the current page.
  final bool registerForPageSearchFab;

  @override
  ConsumerState<LibraryItemSearchField> createState() => _LibraryItemSearchFieldState();
}

class _LibraryItemSearchFieldState extends ConsumerState<LibraryItemSearchField> {
  static const double _fontSize = 13;
  static const double _iconSize = 18;
  static const double _fieldHeight = 36;

  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    if (widget.registerForPageSearchFab) {
      _scheduleSearchFabRegistration(register: true);
    }
  }

  /// Riverpod forbids mutating providers during build/update; defer registry changes.
  void _scheduleSearchFabRegistration({required bool register}) {
    final registry = ref.read(librarySearchFocusRegistryProvider.notifier);
    final node = _focusNode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (register) {
        if (!mounted) {
          return;
        }
        registry.register(node);
      } else {
        registry.unregister(node);
      }
    });
  }

  @override
  void didUpdateWidget(LibraryItemSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registerForPageSearchFab == widget.registerForPageSearchFab) {
      return;
    }
    if (oldWidget.registerForPageSearchFab) {
      _scheduleSearchFabRegistration(register: false);
    }
    if (widget.registerForPageSearchFab) {
      _scheduleSearchFabRegistration(register: true);
    }
  }

  @override
  void deactivate() {
    if (widget.registerForPageSearchFab) {
      _scheduleSearchFabRegistration(register: false);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: _fontSize,
      height: 1.2,
    );
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: _fontSize,
      height: 1.2,
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: _fieldHeight,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        style: textStyle,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTapOutside: (_) => _focusNode.unfocus(),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: hintStyle,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: Icon(Icons.search, size: _iconSize, color: scheme.onSurfaceVariant),
          prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: widget.trailing ??
              (widget.controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      onPressed: () {
                        widget.controller.clear();
                        widget.onChanged('');
                      },
                      icon: Icon(Icons.clear, size: _iconSize, color: scheme.onSurfaceVariant),
                    )),
          suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
        ),
      ),
    );
  }
}
