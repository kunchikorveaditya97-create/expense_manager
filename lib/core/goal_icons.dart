import 'package:flutter/material.dart';

const Map<String, IconData> goalIcons = {
  'savings': Icons.savings,
  'laptop': Icons.laptop,
  'phone': Icons.phone_android,
  'car': Icons.directions_car,
  'home': Icons.home,
  'flight': Icons.flight,
  'school': Icons.school,
  'gift': Icons.card_giftcard,
  'fitness': Icons.fitness_center,
  'health': Icons.favorite,
};

IconData goalIcon(String key) => goalIcons[key] ?? Icons.savings;