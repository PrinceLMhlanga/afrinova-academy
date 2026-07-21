import 'package:flutter/material.dart';
import 'poll_models.dart';

class CreatePollDialog extends StatefulWidget {
  final Function(String question, List<String> options) onCreate;

  const CreatePollDialog({super.key, required this.onCreate});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
    });
  }

  void _create() {
  final question = _questionController.text.trim();
  if (question.isEmpty) return;
  
  final options = _optionControllers
      .map((c) => c.text.trim())
      .where((o) => o.isNotEmpty)
      .toList();
  
  if (options.length < 2) return;
  
  // ✅ Call the callback first
  widget.onCreate(question, options);
  
  // ✅ Then pop just the dialog
  Navigator.of(context).pop();
}

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.poll, color: Color(0xFF1A237E), size: 24),
          const SizedBox(width: 8),
          const Text('Create Poll', style: TextStyle(fontSize: 20)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _questionController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Question',
                hintText: 'e.g., What topic should we cover next?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ..._optionControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Option ${index + 1}',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.red),
                        onPressed: () => _removeOption(index),
                      ),
                  ],
                ),
              );
            }),
            if (_optionControllers.length < 6)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add option'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Launch Poll 🚀'),
        ),
      ],
    );
  }
}

class PollResultCard extends StatelessWidget {
  final Poll poll;
  final bool showVoteButton;
  final Function(int)? onVote;
  final VoidCallback? onClose;

  const PollResultCard({
    super.key,
    required this.poll,
    this.showVoteButton = false,
    this.onVote,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final total = poll.votes.values.fold(0, (a, b) => a + b);
    final hasVoted = poll.participantVotes.isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.poll, color: Color(0xFF1A237E), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    poll.question,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                  ),
              ],
            ),
            
            if (poll.isActive)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            
            const SizedBox(height: 12),
            
            // Options
            ...poll.options.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              final votes = poll.votes[index.toString()] ?? 0;
              final percent = total > 0 ? votes / total * 100 : 0.0;
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: showVoteButton
                    ? _buildVoteButton(index, option)
                    : _buildResultBar(index, option, votes, percent, total),
              );
            }),
            
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '$total vote${total != 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            
            // Close button for teacher
            if (onClose != null && poll.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onClose,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close Poll'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoteButton(int index, String option) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => onVote?.call(index),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade100,
          foregroundColor: const Color(0xFF1A237E),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Text(option, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildResultBar(int index, String option, int votes, double percent, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(option, style: const TextStyle(fontSize: 13)),
            ),
            Text(
              '${percent.toStringAsFixed(0)}% ($votes)',
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percent / 100,
            backgroundColor: Colors.grey.shade200,
            color: const Color(0xFF1A237E),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}