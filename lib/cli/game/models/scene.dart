import 'choice.dart';
import 'random_event.dart';

/// Scene/narrative block in the game
class Scene {
  final String id;
  final String name;
  final String description;
  final List<Choice> choices;
  final List<RandomEvent> randomEvents;

  Scene({
    required this.id,
    required this.name,
    this.description = '',
    List<Choice>? choices,
    List<RandomEvent>? randomEvents,
  })  : choices = choices ?? [],
        randomEvents = randomEvents ?? [];

  /// Check if scene is an end scene (no choices and no random events that redirect)
  bool get isEndScene => choices.isEmpty && randomEvents.isEmpty;
}
