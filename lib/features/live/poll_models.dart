class Poll {
  final String id;
  final String question;
  final List<String> options;
  bool isActive;
  final Map<String, int> votes; // optionIndex -> count
  final Map<String, int> participantVotes; // participantId -> optionIndex
  final DateTime createdAt;
  final String createdBy;

  Poll({
    required this.id,
    required this.question,
    required this.options,
    this.isActive = true,
    Map<String, int>? votes,
    Map<String, int>? participantVotes,
    required this.createdAt,
    required this.createdBy,
  })  : votes = votes ?? {},
        participantVotes = participantVotes ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        'options': options,
        'isActive': isActive,
        'votes': votes,
        'participantVotes': participantVotes,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
      };

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
        id: json['id'],
        question: json['question'],
        options: List<String>.from(json['options']),
        isActive: json['isActive'] ?? true,
        votes: Map<String, int>.from(json['votes'] ?? {}),
        participantVotes: Map<String, int>.from(json['participantVotes'] ?? {}),
        createdAt: DateTime.parse(json['createdAt']),
        createdBy: json['createdBy'],
      );

  // Get results as percentages
  Map<int, double> get percentages {
    final total = votes.values.fold(0, (a, b) => a + b);
    if (total == 0) return {};
    return votes.map((k, v) => MapEntry(int.parse(k), v / total * 100));
  }
}