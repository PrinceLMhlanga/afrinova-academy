import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MathKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onClose;

  const MathKeyboard({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<MathKeyboard> createState() => _MathKeyboardState();
}

class _MathKeyboardState extends State<MathKeyboard> {
  bool _isShiftPressed = false;
  bool _isAlphaPressed = false;
  int _currentPage = 0;
  final int _totalPages = 4;

  final List<String> _pageTitles = ['Basic', 'Functions', 'Greek', 'Symbols'];

  static final Map<int, List<Map<String, String>>> _symbolsByPage = {
    0: [
      {'symbol': '+', 'latex': '+'},
      {'symbol': '−', 'latex': '-'},
      {'symbol': '×', 'latex': '\\times'},
      {'symbol': '÷', 'latex': '\\div'},
      {'symbol': '±', 'latex': '\\pm'},
      {'symbol': '=', 'latex': '='},
      {'symbol': '≠', 'latex': '\\neq'},
      {'symbol': '≈', 'latex': '\\approx'},
      {'symbol': '<', 'latex': '<'},
      {'symbol': '>', 'latex': '>'},
      {'symbol': '≤', 'latex': '\\leq'},
      {'symbol': '≥', 'latex': '\\geq'},
      {'symbol': '°', 'latex': '^{\\circ}'},
      {'symbol': '%', 'latex': '\\%'},
      {'symbol': '½', 'latex': '\\frac{1}{2}'},
      {'symbol': '⅔', 'latex': '\\frac{2}{3}'},
      {'symbol': '⅓', 'latex': '\\frac{1}{3}'},
      {'symbol': '¼', 'latex': '\\frac{1}{4}'},
      {'symbol': '¾', 'latex': '\\frac{3}{4}'},
      {'symbol': '¹', 'latex': '^{1}'},
      {'symbol': '²', 'latex': '^{2}'},
      {'symbol': '³', 'latex': '^{3}'},
      {'symbol': 'ⁿ', 'latex': '^{n}'},
    ],
    1: [
      {'symbol': 'a/b', 'latex': '\\frac{}{}'},
      {'symbol': '√', 'latex': '\\sqrt{}'},
      {'symbol': '∛', 'latex': '\\sqrt[3]{}'},
      {'symbol': '∫ dx', 'latex': '\\int \\, dx'},
      {'symbol': '∫ₐᵇ', 'latex': '\\int_{}^{} \\, dx'},
      {'symbol': '∬', 'latex': '\\iint'},
      {'symbol': '∮', 'latex': '\\oint'},
      {'symbol': '∂', 'latex': '\\partial'},
      {'symbol': '∇', 'latex': '\\nabla'},
      {'symbol': 'lim', 'latex': '\\lim_{x \\to }'},
      {'symbol': '∞', 'latex': '\\infty'},
      {'symbol': 'sin', 'latex': '\\sin'},
      {'symbol': 'cos', 'latex': '\\cos'},
      {'symbol': 'tan', 'latex': '\\tan'},
      {'symbol': 'sin⁻¹', 'latex': '\\sin^{-1}'},
      {'symbol': 'cos⁻¹', 'latex': '\\cos^{-1}'},
      {'symbol': 'tan⁻¹', 'latex': '\\tan^{-1}'},
      {'symbol': 'log', 'latex': '\\log'},
      {'symbol': 'ln', 'latex': '\\ln'},
      {'symbol': 'eˣ', 'latex': 'e^{}'},
    ],
    2: [
      {'symbol': 'α', 'latex': '\\alpha'},
      {'symbol': 'β', 'latex': '\\beta'},
      {'symbol': 'γ', 'latex': '\\gamma'},
      {'symbol': 'δ', 'latex': '\\delta'},
      {'symbol': 'ε', 'latex': '\\epsilon'},
      {'symbol': 'θ', 'latex': '\\theta'},
      {'symbol': 'λ', 'latex': '\\lambda'},
      {'symbol': 'μ', 'latex': '\\mu'},
      {'symbol': 'π', 'latex': '\\pi'},
      {'symbol': 'ρ', 'latex': '\\rho'},
      {'symbol': 'σ', 'latex': '\\sigma'},
      {'symbol': 'φ', 'latex': '\\phi'},
      {'symbol': 'ω', 'latex': '\\omega'},
      {'symbol': 'Δ', 'latex': '\\Delta'},
      {'symbol': 'Σ', 'latex': '\\sum_{}^{}'},
      {'symbol': 'Π', 'latex': '\\prod_{}^{}'},
      {'symbol': 'Ω', 'latex': '\\Omega'},
      {'symbol': 'Γ', 'latex': '\\Gamma'},
      {'symbol': 'Θ', 'latex': '\\Theta'},
      {'symbol': 'Λ', 'latex': '\\Lambda'},
    ],
    3: [
      {'symbol': '→', 'latex': '\\rightarrow'},
      {'symbol': '←', 'latex': '\\leftarrow'},
      {'symbol': '⇌', 'latex': '\\rightleftharpoons'},
      {'symbol': '↑', 'latex': '\\uparrow'},
      {'symbol': '↓', 'latex': '\\downarrow'},
      {'symbol': 'H₂O', 'latex': '\\ce{H2O}'},
      {'symbol': 'CO₂', 'latex': '\\ce{CO2}'},
      {'symbol': 'NaCl', 'latex': '\\ce{NaCl}'},
      {'symbol': 'F=ma', 'latex': 'F = ma'},
      {'symbol': 'E=mc²', 'latex': 'E = mc^{2}'},
      {'symbol': 'Ω', 'latex': '\\,\\Omega'},
      {'symbol': 'V', 'latex': '\\,V'},
      {'symbol': 'A', 'latex': '\\,A'},
      {'symbol': 'W', 'latex': '\\,W'},
      {'symbol': 'm/s²', 'latex': '\\,m/s^{2}'},
      {'symbol': 'km/h', 'latex': '\\,km/h'},
      {'symbol': '∠', 'latex': '\\angle'},
      {'symbol': '∥', 'latex': '\\parallel'},
      {'symbol': '⊥', 'latex': '\\perp'},
      {'symbol': '△', 'latex': '\\triangle'},
      {'symbol': '□', 'latex': '\\square'},
      {'symbol': '°C', 'latex': '^{\\circ}C'},
      {'symbol': '°F', 'latex': '^{\\circ}F'},
    ],
  };

  void _insertSymbol(String latex) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;

    final beforeCursor = text.substring(0, start);
    final afterCursor = text.substring(end);
    
    final dollarCount = r'$'.allMatches(beforeCursor).length;
    final isInMathMode = dollarCount % 2 == 1;
    
    String insertText;
    final needsMathMode = !['+', '-', '=', '<', '>', '(', ')', '[', ']', ',', '.'].contains(latex);
    
    if (isInMathMode) {
      if (needsMathMode) {
        insertText = latex;
      } else {
        final nextChar = afterCursor.isNotEmpty ? afterCursor[0] : '';
        if (nextChar == r'$') {
          insertText = '$latex\$';
        } else {
          insertText = latex;
        }
      }
    } else {
      if (needsMathMode) {
        insertText = '\$$latex\$';
      } else {
        insertText = latex;
      }
    }

    final newText = text.substring(0, start) + insertText + text.substring(end);
    
    int cursorOffset;
    if (insertText.contains(r'$') && needsMathMode) {
      final openingDollarPos = insertText.indexOf(r'$');
      cursorOffset = start + openingDollarPos + latex.length;
      if (insertText.substring(openingDollarPos + 1 + latex.length).startsWith(r'$')) {
        cursorOffset += 1;
      }
    } else {
      cursorOffset = start + insertText.length;
    }
    
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursorOffset),
    );
  }

  void _insertFraction() => _insertSymbol(r'\frac{}{}');
  void _insertSquareRoot() => _insertSymbol(r'\sqrt{}');
  void _insertIntegral() => _insertSymbol(r'\int_{}^{} \, dx');
  void _insertSummation() => _insertSymbol(r'\sum_{}^{}');
  void _insertLimit() => _insertSymbol(r'\lim_{x \to }');
  void _insertPower() => _insertSymbol(r'^{}');
  void _insertSubscript() => _insertSymbol(r'_{}');

  @override
  Widget build(BuildContext context) {
    final symbols = _symbolsByPage[_currentPage] ?? [];
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final isMediumScreen = screenWidth < 500;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ RESPONSIVE Top toolbar
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 4 : 8, 
              vertical: isSmallScreen ? 2 : 4,
            ),
            color: Colors.white,
            child: isSmallScreen 
                ? _buildCompactToolbar()   // Very small screens
                : isMediumScreen 
                    ? _buildMediumToolbar() // Medium screens
                    : _buildFullToolbar(),  // Large screens
          ),
          const Divider(height: 1),
          // Symbol grid - responsive columns
          SizedBox(
            height: isSmallScreen ? 130 : 150,
            child: GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isSmallScreen ? 6 : 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: isSmallScreen ? 1.1 : 1.2,
              ),
              itemCount: symbols.length,
              itemBuilder: (context, index) {
                final symbol = symbols[index];
                return _SymbolButton(
                  symbol: symbol['symbol']!,
                  latex: symbol['latex']!,
                  onTap: () => _insertSymbol(symbol['latex']!),
                  isSmall: isSmallScreen,
                );
              },
            ),
          ),
          // Page dots
          Container(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (index) {
                return Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? const Color(0xFF1A237E)
                        : Colors.grey.shade300,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Full toolbar for large screens
  Widget _buildFullToolbar() {
    return Row(
      children: [
        _QuickActionButton(label: 'a/b', onTap: _insertFraction, tooltip: 'Fraction'),
        const SizedBox(width: 4),
        _QuickActionButton(label: '√', onTap: _insertSquareRoot, tooltip: 'Square Root'),
        const SizedBox(width: 4),
        _QuickActionButton(label: 'x²', onTap: _insertPower, tooltip: 'Power'),
        const SizedBox(width: 4),
        _QuickActionButton(label: 'x₂', onTap: _insertSubscript, tooltip: 'Subscript'),
        const SizedBox(width: 4),
        _QuickActionButton(label: '∫', onTap: _insertIntegral, tooltip: 'Integral'),
        const SizedBox(width: 4),
        _QuickActionButton(label: 'Σ', onTap: _insertSummation, tooltip: 'Summation'),
        const SizedBox(width: 4),
        _QuickActionButton(label: 'lim', onTap: _insertLimit, tooltip: 'Limit'),
        const Spacer(),
        _buildPageNavigation(),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: widget.onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  // ✅ Medium toolbar - fewer quick actions
  Widget _buildMediumToolbar() {
    return Row(
      children: [
        _QuickActionButton(label: 'a/b', onTap: _insertFraction, tooltip: 'Fraction'),
        const SizedBox(width: 2),
        _QuickActionButton(label: '√', onTap: _insertSquareRoot, tooltip: 'Root'),
        const SizedBox(width: 2),
        _QuickActionButton(label: 'x²', onTap: _insertPower, tooltip: 'Power'),
        const SizedBox(width: 2),
        _QuickActionButton(label: '∫', onTap: _insertIntegral, tooltip: 'Integral'),
        const SizedBox(width: 2),
        _QuickActionButton(label: 'Σ', onTap: _insertSummation, tooltip: 'Sum'),
        const Spacer(),
        _buildPageNavigation(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: widget.onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  // ✅ Compact toolbar for very small screens - just page nav + close
  Widget _buildCompactToolbar() {
    return Row(
      children: [
        // Scrollable quick actions
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _QuickActionButton(label: 'a/b', onTap: _insertFraction, tooltip: 'Fraction', compact: true),
                const SizedBox(width: 2),
                _QuickActionButton(label: '√', onTap: _insertSquareRoot, tooltip: 'Root', compact: true),
                const SizedBox(width: 2),
                _QuickActionButton(label: 'x²', onTap: _insertPower, tooltip: 'Power', compact: true),
                const SizedBox(width: 2),
                _QuickActionButton(label: '∫', onTap: _insertIntegral, tooltip: '∫', compact: true),
              ],
            ),
          ),
        ),
        _buildPageNavigation(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: widget.onClose,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  // Page navigation widget
  Widget _buildPageNavigation() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 18),
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          _pageTitles[_currentPage],
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A237E),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 18),
          onPressed: _currentPage < _totalPages - 1 ? () => setState(() => _currentPage++) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SymbolButton extends StatelessWidget {
  final String symbol;
  final String latex;
  final VoidCallback onTap;
  final bool isSmall;

  const _SymbolButton({
    required this.symbol,
    required this.latex,
    required this.onTap,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(isSmall ? 6 : 8),
      elevation: 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isSmall ? 6 : 8),
        child: Center(
          child: Text(
            symbol,
            style: TextStyle(
              fontSize: isSmall ? 13 : 15,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF1A237E),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final String tooltip;
  final bool compact;

  const _QuickActionButton({
    required this.label,
    required this.onTap,
    required this.tooltip,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFF1A237E).withOpacity(0.08),
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 4 : 6),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8, 
              vertical: compact ? 4 : 6,
            ),
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF1A237E),
                fontWeight: FontWeight.w600,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}