import 'dart:math' show pi;
import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<DeckItem> _decks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  Future<void> _loadDecks() async {
    final decks = await StudyStorage.instance.loadDecks();
    if (mounted) setState(() { _decks = decks; _loading = false; });
  }

  Future<void> _save() => StudyStorage.instance.saveDecks(_decks);

  void _addDeck(String name, String subject) {
    setState(() => _decks.add(DeckItem(id: StudyStorage.instance.newId, name: name, subject: subject)));
    _save();
  }

  void _deleteDeck(int index) {
    setState(() => _decks.removeAt(index));
    _save();
  }

  void _onDeckUpdated(DeckItem updated) {
    final i = _decks.indexWhere((d) => d.id == updated.id);
    if (i != -1) setState(() => _decks[i] = updated);
    _save();
  }

  void _addCardToDeck(DeckItem deck, String front, String back) {
    deck.cards.add(FlashCard(front: front, back: back));
    _save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Flashcards'),
        actions: [
          IconButton(icon: const Icon(Icons.add_card_outlined), onPressed: () => _showAddDeckDialog(context)),
        ],
      ),
      body: Stack(
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _decks.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _decks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                      itemBuilder: (context, i) => _DeckCard(
                        deck: _decks[i],
                        onStudy: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _StudyMode(deck: _decks[i], onDeckUpdated: _onDeckUpdated),
                            ),
                          );
                        },
                        onAddCard: () => _showAddCardDialog(context, _decks[i]),
                        onDelete: () => _deleteDeck(i),
                      ),
                    ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: AppColors.accent,
        onPressed: () => _showAddDeckDialog(context),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Deck', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.style_outlined, size: 52, color: AppColors.onSurfaceTertiary),
          const SizedBox(height: AppSpacing.md),
          const Text('No decks yet', style: TextStyle(color: AppColors.onSurfaceSecondary)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () => _showAddDeckDialog(context),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            icon: const Icon(Icons.add),
            label: const Text('Create your first deck'),
          ),
        ],
      ),
    );
  }

  void _showAddDeckDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('New Deck'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Deck name (e.g. Linear Algebra)')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: subjectCtrl, decoration: const InputDecoration(hintText: 'Subject (e.g. Mathematics)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                _addDeck(nameCtrl.text.trim(), subjectCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showAddCardDialog(BuildContext context, DeckItem deck) {
    final frontCtrl = TextEditingController();
    final backCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Add Card to “${deck.name}”'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: frontCtrl, autofocus: true, maxLines: 2, decoration: const InputDecoration(hintText: 'Front — question')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: backCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Back — answer')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (frontCtrl.text.trim().isNotEmpty && backCtrl.text.trim().isNotEmpty) {
                _addCardToDeck(deck, frontCtrl.text.trim(), backCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ─── Deck list card ───────────────────────────────────────────────────────────

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.deck, required this.onStudy, required this.onAddCard, required this.onDelete});

  final DeckItem deck;
  final VoidCallback onStudy;
  final VoidCallback onAddCard;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = deck.total == 0 ? 0.0 : deck.mastered / deck.total;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deck.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(deck.subject, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.onSurfaceTertiary, size: 18),
                color: AppColors.surfaceElevated,
                onSelected: (v) {
                  if (v == 'add') onAddCard();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Add card')),
                  PopupMenuItem(value: 'delete', child: Text('Delete deck', style: TextStyle(color: AppColors.error))),
                ],
              ),
              if (deck.total > 0)
                FilledButton(
                  onPressed: onStudy,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
                  child: const Text('Study'),
                )
              else
                TextButton(onPressed: onAddCard, child: const Text('Add cards')),
            ],
          ),
          if (deck.total > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.divider,
                      valueColor: const AlwaysStoppedAnimation(AppColors.studyGreen),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text('${deck.mastered}/${deck.total}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.studyGreen, fontWeight: FontWeight.w600)),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('No cards yet — tap “Add cards” to start', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

// ─── Study mode ───────────────────────────────────────────────────────────────

class _StudyMode extends StatefulWidget {
  const _StudyMode({required this.deck, required this.onDeckUpdated});
  final DeckItem deck;
  final void Function(DeckItem) onDeckUpdated;

  @override
  State<_StudyMode> createState() => _StudyModeState();
}

class _StudyModeState extends State<_StudyMode>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  bool _showBack = false;
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  late final DeckItem _deck;

  @override
  void initState() {
    super.initState();
    // Deep-copy cards so mutations don’t affect the original until saved on exit.
    _deck = DeckItem(
      id: widget.deck.id,
      name: widget.deck.name,
      subject: widget.deck.subject,
      cards: widget.deck.cards
          .map((c) => FlashCard(front: c.front, back: c.back, mastered: c.mastered))
          .toList(),
    );
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
    _anim = Tween<double>(begin: 0, end: pi)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    widget.onDeckUpdated(_deck); // persist mastered state
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    _showBack ? _ctrl.reverse() : _ctrl.forward();
    setState(() => _showBack = !_showBack);
  }

  void _grade(bool correct) {
    if (_index < _deck.cards.length) _deck.cards[_index].mastered = correct;
    StudyStorage.instance.recordActivity();
    if (_index < _deck.cards.length - 1) {
      setState(() { _index++; _showBack = false; });
      _ctrl.reset();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_deck.cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.deck.name)),
        body: const Center(child: Text('No cards in this deck.')),
      );
    }
    final card = _deck.cards[_index];
    final total = _deck.cards.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.deck.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: (_index + 1) / total,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            minHeight: 3,
          ),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Text(
                  'Card ${_index + 1} of $total',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                Expanded(
                  child: GestureDetector(
                    onTap: _flip,
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (context, _) {
                        final angle = _anim.value;
                        final showFront = angle < pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: showFront
                            ? _CardFace(text: card.front, label: 'QUESTION', color: AppColors.accent)
                            : Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..rotateY(pi),
                                child: _CardFace(text: card.back, label: 'ANSWER', color: AppColors.studyGreen),
                                ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Tap card to flip',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton.filled(
                      onPressed: _index > 0 ? () { setState(() { _index--; _showBack = false; }); _ctrl.reset(); } : null,
                      icon: const Icon(Icons.arrow_back),
                      style: IconButton.styleFrom(backgroundColor: AppColors.surface),
                    ),
                    if (_showBack) ...[
                      FilledButton.icon(
                        onPressed: () => _grade(false),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Again'),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                      ),
                      FilledButton.icon(
                        onPressed: () => _grade(true),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Got it'),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.studyGreen),
                      ),
                    ],
                    IconButton.filled(
                      onPressed: _index < total - 1 ? () { setState(() { _index++; _showBack = false; }); _ctrl.reset(); } : null,
                      icon: const Icon(Icons.arrow_forward),
                      style: IconButton.styleFrom(backgroundColor: AppColors.surface),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({required this.text, required this.label, required this.color});

  final String text;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withOpacity(0.4), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
