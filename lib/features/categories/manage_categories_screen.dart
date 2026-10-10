import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/category_icons.dart';
import '../../data/local/app_database.dart';
import '../../data/local/tables.dart';
import '../../providers/category_provider.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen> {
  TransactionType _type = TransactionType.expense;

  void _openSheet(Category? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(existing: existing, type: _type),
    );
  }

  void _toggleArchive(CategoryProvider cp, Category c) {
    final active = cp.activeNames(_type).length;
    if (!c.isArchived && active <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one active category.')),
      );
      return;
    }
    cp.setArchived(c.id, !c.isArchived);
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<CategoryProvider>();
    final list = cp.forType(_type);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSheet(null),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<TransactionType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: TransactionType.expense, label: Text('Expense')),
                ButtonSegment(
                    value: TransactionType.income, label: Text('Income')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in list)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                      _color(c).withValues(alpha: c.isArchived ? 0.08 : 0.15),
                      child: Icon(categoryIcon(c.iconName),
                          color: c.isArchived ? Colors.grey : _color(c)),
                    ),
                    title: Text(
                      c.name,
                      style: c.isArchived
                          ? const TextStyle(
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Text(c.isArchived
                        ? 'Archived'
                        : (c.isCustom ? 'Custom' : 'Default')),
                    trailing: IconButton(
                      tooltip: c.isArchived ? 'Restore' : 'Archive',
                      icon: Icon(c.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined),
                      onPressed: () => _toggleArchive(cp, c),
                    ),
                    onTap: () => _openSheet(c),
                  ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _color(Category c) => c.colorValue != null
      ? Color(c.colorValue!)
      : Theme.of(context).colorScheme.primary;
}

class _CategorySheet extends StatefulWidget {
  final Category? existing;
  final TransactionType type;
  const _CategorySheet({this.existing, required this.type});

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final TextEditingController _name;
  late String _icon;
  int? _color;
  String? _error;

  static const _colors = [
    0xFFEF5350, 0xFFFFA726, 0xFFFFEE58, 0xFF66BB6A,
    0xFF26C6DA, 0xFF42A5F5, 0xFF7E57C2, 0xFFEC407A,
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _icon = widget.existing?.iconName ?? 'category';
    _color = widget.existing?.colorValue;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cp = context.read<CategoryProvider>();
    if (widget.existing != null) {
      await cp.updateStyle(widget.existing!.id, _icon, _color);
    } else {
      final err = await cp.add(_name.text, widget.type, _icon, _color);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(editing ? 'Edit Category' : 'New Category',
              style:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !editing, // name is the key stored on transactions
            decoration: InputDecoration(
              labelText: 'Name',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Icon'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in categoryIcons.entries)
                ChoiceChip(
                  label: Icon(e.value, size: 20),
                  selected: _icon == e.key,
                  onSelected: (_) => setState(() => _icon = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Color (optional)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              GestureDetector(
                onTap: () => setState(() => _color = null),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey.shade300,
                  child: _color == null
                      ? const Icon(Icons.check, size: 16)
                      : const Icon(Icons.block, size: 16),
                ),
              ),
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(c),
                    child: _color == c
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}