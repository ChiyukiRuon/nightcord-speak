// The row every screen-share setting is built from.

import 'package:flutter/material.dart';

import '../../../design/theme/app_theme.dart';

/// One setting: a question mark, a name, and the control.
///
/// The mark is the reference client's, and it is not decoration — half of these
/// rows are numbers where the honest answer is "it depends what you are
/// sharing", and a tooltip is the only place that fits without turning the page
/// into an essay.
class SetupRow extends StatelessWidget {
  const SetupRow({required this.label, required this.help, required this.control, super.key});

  final String label;

  /// What the mark says. Required: a mark that explains nothing is worse than
  /// no mark, because it teaches people the marks say nothing.
  final String help;

  final Widget control;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.space2),
      child: Row(
        children: [
          Tooltip(
            message: help,
            child: Icon(Icons.help_outline, size: 16, color: tokens.textTertiary),
          ),
          SizedBox(width: AppSpacing.space2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
          ),
          SizedBox(width: AppSpacing.space4),
          // Right-aligned rather than stretched: a segmented control that fills
          // the row reads as a toolbar, and the eye has further to travel from
          // the name to the choice.
          Expanded(child: Align(alignment: Alignment.centerRight, child: control)),
        ],
      ),
    );
  }
}

/// A heading that groups the rows under it.
class SetupSection extends StatelessWidget {
  const SetupSection({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.space2, bottom: AppSpacing.space1),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: tokens.primary),
        ),
      ),
    );
  }
}

/// One of a few named choices, in the reference client's pill form.
class SetupChoice<T> extends StatelessWidget {
  const SetupChoice({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  /// The chosen value, or null when nothing matches — which is how a manual
  /// edit shows up as "your own" rather than as a preset the numbers are not.
  final T? value;

  /// Each option, and whether it can be picked.
  final List<(T value, String label, bool enabled)> options;

  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Wrap(
      spacing: AppSpacing.space1,
      children: [
        for (final (option, label, enabled) in options)
          _Pill(
            label: label,
            selected: option == value,
            enabled: enabled,
            onPressed: () => onChanged(option),
            tokens: tokens,
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    required this.tokens,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final DesignTokens tokens;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? tokens.primary : tokens.surface2,
    borderRadius: AppRadius.smAll,
    child: InkWell(
      onTap: enabled && !selected ? onPressed : null,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: !enabled
                ? tokens.textDisabled
                : selected
                ? tokens.textOnPrimary
                : tokens.textSecondary,
          ),
        ),
      ),
    ),
  );
}

/// A number with a minus and a plus either side.
///
/// Buttons rather than a slider: these are values people arrive at by thinking
/// ("a bit more than last time"), and a slider on a 5000-wide range cannot be
/// aimed at the number someone has in mind.
class SetupStepper extends StatelessWidget {
  const SetupStepper({
    required this.text,
    required this.unit,
    required this.onStep,
    this.canDecrease = true,
    this.canIncrease = true,
    super.key,
  });

  /// The number as it should read — which is not always the number itself: a
  /// viewer limit of zero is "Unlimited" and says so here.
  final String text;

  /// What the number is in, shown after it. Empty when it needs no unit.
  final String unit;

  final ValueChanged<int> onStep;
  final bool canDecrease;
  final bool canIncrease;

  @override
  Widget build(BuildContext context) {
    final tokens = DesignTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove,
          enabled: canDecrease,
          onPressed: () => onStep(-1),
          tokens: tokens,
        ),
        SizedBox(
          // Wide enough for the longest of these to stay centred while it is
          // being stepped, so the digits do not make the buttons jump.
          width: 96,
          child: Text(
            unit.isEmpty ? text : '$text $unit',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
          ),
        ),
        _StepButton(
          icon: Icons.add,
          enabled: canIncrease,
          onPressed: () => onStep(1),
          tokens: tokens,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
    required this.tokens,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final DesignTokens tokens;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: enabled ? onPressed : null,
    icon: Icon(icon, size: 18),
    color: tokens.textSecondary,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 32, height: 32),
  );
}
