/// Utility for detecting the current time of day and providing
/// matching greetings, emoji, and meal-type suggestions.
///
/// Time periods:
///   - Morning:   5:00  – 11:59
///   - Afternoon: 12:00 – 16:59
///   - Evening:   17:00 – 20:59
///   - Night:     21:00 –  4:59
class TimeOfDayUtil {
  TimeOfDayUtil._();

  /// Human-readable period label.
  static const String morning = 'morning';
  static const String afternoon = 'afternoon';
  static const String evening = 'evening';
  static const String night = 'night';

  /// Detect the current time period based on the hour.
  static String get currentPeriod {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return morning;
    if (hour >= 12 && hour < 17) return afternoon;
    if (hour >= 17 && hour < 21) return evening;
    return night;
  }

  /// Friendly greeting with emoji for the given [period].
  /// Defaults to the current period if none provided.
  static String greeting([String? period]) {
    switch (period ?? currentPeriod) {
      case morning:
        return 'Good Morning ☀️';
      case afternoon:
        return 'Good Afternoon 🌤️';
      case evening:
        return 'Good Evening 🌅';
      case night:
        return 'Good Night 🌙';
      default:
        return 'Hello! 👋';
    }
  }

  /// A short greeting without emoji (for accessibility / compact layouts).
  static String plainGreeting([String? period]) {
    switch (period ?? currentPeriod) {
      case morning:
        return 'Good Morning';
      case afternoon:
        return 'Good Afternoon';
      case evening:
        return 'Good Evening';
      case night:
        return 'Good Night';
      default:
        return 'Hello';
    }
  }

  /// Section title for food suggestions that match the current time.
  static String suggestionSectionTitle([String? period]) {
    switch (period ?? currentPeriod) {
      case morning:
        return 'Breakfast Ideas';
      case afternoon:
        return 'Lunch Suggestions';
      case evening:
        return 'Dinner Picks';
      case night:
        return 'Late Night Cravings';
      default:
        return 'Popular Items';
    }
  }

  /// Emoji representing the current meal type.
  static String mealEmoji([String? period]) {
    switch (period ?? currentPeriod) {
      case morning:
        return '🥞';
      case afternoon:
        return '🍛';
      case evening:
        return '🍽️';
      case night:
        return '🌙';
      default:
        return '🍴';
    }
  }

  /// List of menu-item category keywords that restaurants might use
  /// for items matching the given period. These are matched against
  /// the `category` field of menu items (case-insensitive).
  static List<String> matchingCategoryKeywords([String? period]) {
    switch (period ?? currentPeriod) {
      case morning:
        return ['Breakfast', 'Morning', 'Brunch'];
      case afternoon:
        return ['Lunch', 'Main Course', 'Rice', 'Noodles', 'Biriyani'];
      case evening:
        return ['Dinner', 'Main Course', 'Rice', 'Noodles', 'Pizza', 'Momo', 'Burger'];
      case night:
        return []; // empty = show all
      default:
        return [];
    }
  }

  /// True if the given menu item category name matches the current
  /// or specified time period.
  static bool categoryMatches(String category, [String? period]) {
    final keywords = matchingCategoryKeywords(period);
    if (keywords.isEmpty) return true; // night = show all
    final lower = category.toLowerCase();
    return keywords.any((k) => lower.contains(k.toLowerCase()));
  }

  /// How many seconds until the next period change (for auto-refresh timer).
  /// Returns 0 if we're already in the next period (edge case).
  static int secondsUntilNextPeriod() {
    final now = DateTime.now();
    final currentHour = now.hour;

    int nextHour;
    if (currentHour < 5) {
      nextHour = 5; // next morning
    } else if (currentHour < 12) {
      nextHour = 12; // next afternoon
    } else if (currentHour < 17) {
      nextHour = 17; // next evening
    } else if (currentHour < 21) {
      nextHour = 21; // next night
    } else {
      nextHour = 24 + 5; // next morning (tomorrow)
    }

    final next = DateTime(
      now.year,
      now.month,
      now.day + (nextHour >= 24 ? 1 : 0),
      nextHour >= 24 ? nextHour - 24 : nextHour,
      0,
      0,
    );

    return next.difference(now).inSeconds;
  }
}
