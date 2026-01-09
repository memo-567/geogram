import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tracker_plan.dart';
import '../models/trackable_type.dart';
import '../services/tracker_service.dart';
import '../../services/i18n_service.dart';

/// Dialog for creating a new fitness plan with goals
class CreatePlanDialog extends StatefulWidget {
  final TrackerService service;
  final I18nService i18n;

  const CreatePlanDialog({
    super.key,
    required this.service,
    required this.i18n,
  });

  /// Show the create plan dialog
  static Future<bool?> show(
    BuildContext context, {
    required TrackerService service,
    required I18nService i18n,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => CreatePlanDialog(
        service: service,
        i18n: i18n,
      ),
    );
  }

  @override
  State<CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends State<CreatePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  List<_GoalInput> _goals = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Start with one empty goal
    _addGoal();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    for (final goal in _goals) {
      goal.targetController.dispose();
    }
    super.dispose();
  }

  void _addGoal() {
    final availableExercises = TrackableTypeConfig.exerciseTypes.keys.toList();
    if (availableExercises.isEmpty) return;

    setState(() {
      _goals.add(_GoalInput(
        exerciseId: availableExercises.first,
        targetType: GoalTargetType.weekly,
        targetController: TextEditingController(text: '50'),
      ));
    });
  }

  void _removeGoal(int index) {
    if (_goals.length <= 1) return;
    setState(() {
      _goals[index].targetController.dispose();
      _goals.removeAt(index);
    });
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 28)),
      firstDate: _startDate,
      lastDate: _startDate.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  void _clearEndDate() {
    setState(() => _endDate = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.t('tracker_create_plan')),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title field
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_plan_title'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return widget.i18n.t('tracker_required_field');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description field
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: widget.i18n.t('tracker_plan_description'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Date selection
                Row(
                  children: [
                    Expanded(
                      child: _buildDateField(
                        label: widget.i18n.t('tracker_start_date'),
                        date: _startDate,
                        onTap: _selectStartDate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDateField(
                        label: widget.i18n.t('tracker_end_date'),
                        date: _endDate,
                        onTap: _selectEndDate,
                        onClear: _endDate != null ? _clearEndDate : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Goals section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.i18n.t('tracker_goals'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _addGoal,
                      tooltip: widget.i18n.t('tracker_add_goal'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Goals list
                ..._goals.asMap().entries.map((entry) =>
                    _buildGoalCard(entry.key, entry.value)),

                if (_goals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.i18n.t('tracker_at_least_one_goal'),
                      style: TextStyle(color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(widget.i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.i18n.t('save')),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : null,
        ),
        child: Text(
          date != null ? _formatDate(date) : '-',
          style: date == null ? TextStyle(color: Colors.grey[400]) : null,
        ),
      ),
    );
  }

  Widget _buildGoalCard(int index, _GoalInput goal) {
    final exerciseTypes = TrackableTypeConfig.exerciseTypes;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.i18n.t('tracker_goal')} ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (_goals.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle, color: Colors.red),
                    onPressed: () => _removeGoal(index),
                    tooltip: widget.i18n.t('tracker_remove_goal'),
                    iconSize: 20,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Exercise dropdown
            DropdownButtonFormField<String>(
              value: goal.exerciseId,
              decoration: InputDecoration(
                labelText: widget.i18n.t('tracker_goal_exercise'),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: exerciseTypes.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(widget.i18n.t('tracker_exercise_${e.key}')),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => goal.exerciseId = value);
                }
              },
            ),
            const SizedBox(height: 12),

            // Target type and value
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<GoalTargetType>(
                    value: goal.targetType,
                    decoration: InputDecoration(
                      labelText: widget.i18n.t('tracker_goal_target_type'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: GoalTargetType.daily,
                        child: Text(widget.i18n.t('tracker_goal_daily')),
                      ),
                      DropdownMenuItem(
                        value: GoalTargetType.weekly,
                        child: Text(widget.i18n.t('tracker_goal_weekly')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => goal.targetType = value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: goal.targetController,
                    decoration: InputDecoration(
                      labelText: widget.i18n.t('tracker_target'),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return widget.i18n.t('tracker_required');
                      }
                      final num = int.tryParse(value);
                      if (num == null || num < 1) {
                        return widget.i18n.t('tracker_invalid');
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_goals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.i18n.t('tracker_at_least_one_goal'))),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      // Build goals list
      final goals = <PlanGoal>[];
      for (int i = 0; i < _goals.length; i++) {
        final input = _goals[i];
        final targetValue = int.parse(input.targetController.text);
        final goalId = 'goal_$i';

        if (input.targetType == GoalTargetType.daily) {
          goals.add(PlanGoal.daily(
            id: goalId,
            exerciseId: input.exerciseId,
            description: widget.i18n.t('tracker_exercise_${input.exerciseId}'),
            dailyTarget: targetValue,
          ));
        } else {
          goals.add(PlanGoal.weekly(
            id: goalId,
            exerciseId: input.exerciseId,
            description: widget.i18n.t('tracker_exercise_${input.exerciseId}'),
            weeklyTarget: targetValue,
          ));
        }
      }

      // Create the plan
      final plan = await widget.service.createPlan(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        startsAt: _formatDate(_startDate),
        endsAt: _endDate != null ? _formatDate(_endDate!) : null,
        goals: goals,
      );

      if (plan != null && mounted) {
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Failed to create plan');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _saving = false);
      }
    }
  }
}

/// Helper class to track goal input state
class _GoalInput {
  String exerciseId;
  GoalTargetType targetType;
  TextEditingController targetController;

  _GoalInput({
    required this.exerciseId,
    required this.targetType,
    required this.targetController,
  });
}
