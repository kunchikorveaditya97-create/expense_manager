import 'package:flutter/material.dart';

const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'flight': Icons.flight,
  'shopping_bag': Icons.shopping_bag,
  'receipt': Icons.receipt_long,
  'home': Icons.home,
  'movie': Icons.movie,
  'health': Icons.favorite,
  'school': Icons.school,
  'subscriptions': Icons.subscriptions,
  'work': Icons.work,
  'laptop': Icons.laptop,
  'business': Icons.business_center,
  'trending_up': Icons.trending_up,
  'gift': Icons.card_giftcard,
  'category': Icons.category,
  'pets': Icons.pets,
  'fitness': Icons.fitness_center,
  'car': Icons.directions_car,
  'phone': Icons.phone_android,
  'coffee': Icons.local_cafe,
};

IconData categoryIcon(String key) => categoryIcons[key] ?? Icons.category;