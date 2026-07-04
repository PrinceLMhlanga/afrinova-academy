import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class CircuitToolbar extends StatelessWidget {
  final void Function(String name, String svgPath) onInsert;

  const CircuitToolbar({super.key, required this.onInsert});

  static const Map<String, Map<String, String>> components = {
    'Resistor': {
      'name': 'Resistor',
      'svg': '''
        <svg viewBox="0 0 100 40">
          <line x1="0" y1="20" x2="15" y2="20" stroke="black" stroke-width="2"/>
          <rect x="15" y="5" width="70" height="30" rx="3" fill="white" stroke="black" stroke-width="2"/>
          <line x1="85" y1="20" x2="100" y2="20" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Battery': {
      'name': 'Battery',
      'svg': '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="20" y2="25" stroke="black" stroke-width="2"/>
          <rect x="20" y="5" width="60" height="40" rx="5" fill="white" stroke="black" stroke-width="2"/>
          <line x1="30" y1="20" x2="30" y2="30" stroke="black" stroke-width="3"/>
          <line x1="35" y1="15" x2="35" y2="35" stroke="black" stroke-width="3"/>
          <line x1="80" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Switch (Open)': {
      'name': 'Switch',
      'svg': '''
        <svg viewBox="0 0 100 50">
          <circle cx="20" cy="25" r="3" fill="black"/>
          <line x1="0" y1="25" x2="20" y2="25" stroke="black" stroke-width="2"/>
          <circle cx="80" cy="25" r="3" fill="black"/>
          <line x1="80" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
          <line x1="20" y1="25" x2="60" y2="10" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Ammeter': {
      'name': 'Ammeter',
      'svg': '''
        <svg viewBox="0 0 100 50">
          <circle cx="50" cy="25" r="22" fill="white" stroke="black" stroke-width="2"/>
          <text x="50" y="31" text-anchor="middle" font-size="16" font-weight="bold" fill="black">A</text>
          <line x1="0" y1="25" x2="28" y2="25" stroke="black" stroke-width="2"/>
          <line x1="72" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Voltmeter': {
      'name': 'Voltmeter',
      'svg': '''
        <svg viewBox="0 0 100 50">
          <circle cx="50" cy="25" r="22" fill="white" stroke="black" stroke-width="2"/>
          <text x="50" y="31" text-anchor="middle" font-size="16" font-weight="bold" fill="black">V</text>
          <line x1="0" y1="25" x2="28" y2="25" stroke="black" stroke-width="2"/>
          <line x1="72" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Light Bulb': {
      'name': 'Bulb',
      'svg': '''
        <svg viewBox="0 0 60 80">
          <circle cx="30" cy="30" r="22" fill="white" stroke="black" stroke-width="2"/>
          <line x1="18" y1="52" x2="42" y2="52" stroke="black" stroke-width="2"/>
          <line x1="21" y1="56" x2="39" y2="56" stroke="black" stroke-width="2"/>
          <line x1="24" y1="60" x2="36" y2="60" stroke="black" stroke-width="2"/>
          <line x1="30" y1="60" x2="30" y2="80" stroke="black" stroke-width="2"/>
          <line x1="0" y1="30" x2="8" y2="30" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Diode': {
      'name': 'Diode',
      'svg': '''
        <svg viewBox="0 0 100 50">
          <line x1="0" y1="25" x2="25" y2="25" stroke="black" stroke-width="2"/>
          <polygon points="25,10 55,25 25,40" fill="white" stroke="black" stroke-width="2"/>
          <line x1="55" y1="10" x2="55" y2="40" stroke="black" stroke-width="2"/>
          <line x1="55" y1="25" x2="100" y2="25" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'Ground': {
      'name': 'Ground',
      'svg': '''
        <svg viewBox="0 0 50 50">
          <line x1="25" y1="0" x2="25" y2="15" stroke="black" stroke-width="2"/>
          <line x1="5" y1="15" x2="45" y2="15" stroke="black" stroke-width="2"/>
          <line x1="12" y1="25" x2="38" y2="25" stroke="black" stroke-width="2"/>
          <line x1="17" y1="35" x2="33" y2="35" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
  };

  // Logic gates
  static const Map<String, Map<String, String>> logicGates = {
    'AND Gate': {
      'name': 'AND',
      'svg': '''
        <svg viewBox="0 0 120 60">
          <path d="M30,5 L30,5 L30,55 L70,55 Q100,55 100,30 Q100,5 70,5 Z" fill="white" stroke="black" stroke-width="2"/>
          <line x1="0" y1="15" x2="30" y2="15" stroke="black" stroke-width="2"/>
          <line x1="0" y1="45" x2="30" y2="45" stroke="black" stroke-width="2"/>
          <line x1="100" y1="30" x2="120" y2="30" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'OR Gate': {
      'name': 'OR',
      'svg': '''
        <svg viewBox="0 0 120 60">
          <path d="M30,5 Q60,5 80,15 Q95,25 95,30 Q95,35 80,45 Q60,55 30,55 Z" fill="white" stroke="black" stroke-width="2"/>
          <path d="M20,5 Q50,15 70,30 Q50,45 20,55" fill="white" stroke="black" stroke-width="2"/>
          <line x1="0" y1="15" x2="25" y2="15" stroke="black" stroke-width="2"/>
          <line x1="0" y1="45" x2="25" y2="45" stroke="black" stroke-width="2"/>
          <line x1="95" y1="30" x2="120" y2="30" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
    'NOT Gate': {
      'name': 'NOT',
      'svg': '''
        <svg viewBox="0 0 100 60">
          <polygon points="30,5 70,30 30,55" fill="white" stroke="black" stroke-width="2"/>
          <circle cx="75" cy="30" r="5" fill="white" stroke="black" stroke-width="2"/>
          <line x1="0" y1="30" x2="30" y2="30" stroke="black" stroke-width="2"/>
          <line x1="80" y1="30" x2="100" y2="30" stroke="black" stroke-width="2"/>
        </svg>
      '''
    },
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Circuit Components',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          ),
          SizedBox(
            height: 55,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: components.entries.map((e) {
                return GestureDetector(
                  onTap: () => onInsert(e.value['name']!, e.value['svg']!),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 25,
                          child: SvgPicture.string(e.value['svg']!),
                        ),
                        const SizedBox(height: 2),
                        Text(e.key, style: const TextStyle(fontSize: 8), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Logic Gates',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          ),
          SizedBox(
            height: 55,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: logicGates.entries.map((e) {
                return GestureDetector(
                  onTap: () => onInsert(e.value['name']!, e.value['svg']!),
                  child: Container(
                    width: 70,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 25,
                          child: SvgPicture.string(e.value['svg']!),
                        ),
                        const SizedBox(height: 2),
                        Text(e.key, style: const TextStyle(fontSize: 8), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}