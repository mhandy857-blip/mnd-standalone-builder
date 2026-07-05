import 'package:mnd_core/mnd_core.dart';
import 'package:mnd_player/services/save_game_provider.dart';
import 'package:mnd_player/providers/quest_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

//  ЭКРАН ЗАГРУЗКИ ИГРЫ — Material You / Material 3 редизайн
//  Визуальный язык согласован с Библиотекой и Профилем.

class LoadGameScreen extends ConsumerWidget {
  final String questId;
  final bool isTesting;

  const LoadGameScreen({
    super.key,
    required this.questId,
    this.isTesting = false,
  });

  String _formatDate(DateTime date) {
    const List<String> months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'мая',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    final day = date.day.toString();
    final month = months[date.month - 1];
    final year = date.year.toString();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day $month $year, $hour:$minute';
  }

  void _startNewGame(BuildContext context, WidgetRef ref) async {
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  void _loadFromSlot(BuildContext context, WidgetRef ref, SaveSlot slot) {
    Navigator.pop(context, slot);
  }

  void _deleteSlot(BuildContext context, WidgetRef ref, SaveSlot slot) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сохранение?'),
        content: Text(
          'Квест «${slot.slotName}» будет удалён без возможности восстановления.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.errorContainer,
              foregroundColor: scheme.onErrorContainer,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(saveGameServiceProvider).deleteSave(questId, slot.id);
      ref.invalidate(saveSlotsProvider(questId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final slotsAsync = ref.watch(saveSlotsProvider(questId));

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              pinned: false,
              floating: true,
              snap: true,
              toolbarHeight: 56,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _LoadGameHero(stats: _SaveStats.fromAsync(slotsAsync)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: _NewGameButton(
                  onPressed: () => _startNewGame(context, ref),
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Ваши сохранения',
                subtitle: 'Продолжите с того места, где остановились',
                icon: Icons.bookmarks_rounded,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            slotsAsync.when(
              loading: () => SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: scheme.primary),
                ),
              ),
              error: (err, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'Ошибка: $err',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ),
              ),
              data: (slots) {
                if (slots.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                      child: _EmptySavesState(),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final isAutosave = slot.id == SaveGameService.autosaveId;
                      return _SaveSlotCard(
                        slot: slot,
                        isAutosave: isAutosave,
                        dateString: _formatDate(slot.savedAt),
                        onTap: () => _loadFromSlot(context, ref, slot),
                        onDelete: () => _deleteSlot(context, ref, slot),
                      );
                    },
                  ),
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

//  СТАТИСТИКА СОХРАНЕНИЙ

class _SaveStats {
  final int total;
  final bool hasAutosave;

  const _SaveStats({required this.total, required this.hasAutosave});

  factory _SaveStats.empty() => const _SaveStats(total: 0, hasAutosave: false);

  factory _SaveStats.fromAsync(AsyncValue<List<SaveSlot>> async) {
    return async.maybeWhen(
      data: (list) => _SaveStats(
        total: list.length,
        hasAutosave: list.any((s) => s.id == SaveGameService.autosaveId),
      ),
      orElse: _SaveStats.empty,
    );
  }
}

//  HERO-СЕКЦИЯ

class _LoadGameHero extends StatelessWidget {
  final _SaveStats stats;

  const _LoadGameHero({required this.stats});

  String _buildSubtitle() {
    if (stats.total == 0) {
      return 'Пока нет сохранений — начните новую игру';
    }
    final word = _plural(stats.total, 'сохранение', 'сохранения', 'сохранений');
    final parts = <String>['${stats.total} $word'];
    if (stats.hasAutosave) parts.add('автосейв активен');
    return parts.join(' · ');
  }

  String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return few;
    return many;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            Color.alphaBlend(
              scheme.secondaryContainer.withOpacity(0.6),
              scheme.primaryContainer,
            ),
          ],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -22,
            bottom: -30,
            child: Icon(
              Icons.save_rounded,
              size: 170,
              color: scheme.onPrimaryContainer.withOpacity(0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Сохранения',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _buildSubtitle(),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withOpacity(0.78),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

//  КНОПКА «НАЧАТЬ ЗАНОВО»

class _NewGameButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _NewGameButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: const Icon(Icons.play_arrow_rounded, size: 26),
        label: const Text(
          'Начать заново',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

//  SECTION HEADER

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  const _SectionHeader({
    required this.title,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

//  КАРТОЧКА СОХРАНЕНИЯ

class _SaveSlotCard extends StatelessWidget {
  final SaveSlot slot;
  final String dateString;
  final bool isAutosave;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SaveSlotCard({
    required this.slot,
    required this.dateString,
    this.isAutosave = false,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isAutosave
                      ? scheme.tertiaryContainer
                      : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isAutosave ? Icons.history_rounded : Icons.bookmark_rounded,
                  color: isAutosave
                      ? scheme.onTertiaryContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isAutosave ? 'Автосохранение' : slot.slotName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAutosave) ...[
                          const SizedBox(width: 6),
                          _Badge(
                            icon: Icons.bolt_rounded,
                            tooltip: 'Создаётся автоматически',
                            color: scheme.tertiaryContainer,
                            iconColor: scheme.onTertiaryContainer,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateString,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                tooltip: 'Удалить сохранение',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color iconColor;

  const _Badge({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 13, color: iconColor),
      ),
    );
  }
}

//  ПУСТОЕ СОСТОЯНИЕ

class _EmptySavesState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bookmark_border_rounded,
                size: 44,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Пока нет сохранений',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Начните новую игру. Прогресс сохраняется автоматически при выходе, '
              'также вы можете сохраняться вручную.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
