class DemoLocations {
  static const List<String> destinations = [
    "Admin Block",
    "Main Block",
    "New Block",
    "Old Block",
    "Library",
    "Office",
    "Canteen",
    "Auditorium",
    "Restroom",
    "CS 102",
    "CS one zero two",
    "New Block CS 105",
    "S7 CS",
    "S seven CS"
  ];

  static Map<String, List<Map<String, dynamic>>> routes = {
    "library": [
      {"action": "GO STRAIGHT", "description": "Walk forward for 10 meters towards the main corridor.", "direction": "up", "duration": 4},
      {"action": "TURN LEFT", "description": "Turn left near the staircase.", "direction": "left", "duration": 4},
      {"action": "GO STRAIGHT", "description": "Walk forward for 5 meters. The library is on your right.", "direction": "up", "duration": 4},
      {"action": "ARRIVED", "description": "You have reached the Library.", "direction": "stop", "duration": 2},
    ],
    "admin block": [
      {"action": "GO STRAIGHT", "description": "Walk straight through the main entrance.", "direction": "up", "duration": 3},
      {"action": "TURN RIGHT", "description": "Turn right at the reception desk.", "direction": "right", "duration": 3},
      {"action": "GO STRAIGHT", "description": "Walk straight for 10 meters.", "direction": "up", "duration": 5},
      {"action": "ARRIVED", "description": "You have reached the Admin Block.", "direction": "stop", "duration": 2},
    ],
    "cs 102": [
      {"action": "GO STRAIGHT", "description": "Walk straight along the CS department corridor.", "direction": "up", "duration": 3},
      {"action": "TURN LEFT", "description": "Turn left at the water cooler.", "direction": "left", "duration": 3},
      {"action": "GO STRAIGHT", "description": "CS 102 is the second door on your left.", "direction": "up", "duration": 3},
      {"action": "ARRIVED", "description": "You have reached CS 102.", "direction": "stop", "duration": 2},
    ],
     "s7 cs": [
      {"action": "GO STRAIGHT", "description": "Walk straight towards the New Block.", "direction": "up", "duration": 3},
      {"action": "TURN LEFT", "description": "Turn left and take the stairs to the first floor.", "direction": "left", "duration": 3},
      {"action": "GO STRAIGHT", "description": "S7 CS class is at the end of the hall.", "direction": "up", "duration": 3},
      {"action": "ARRIVED", "description": "You have reached S7 CS.", "direction": "stop", "duration": 2},
    ],
  };

  static List<Map<String, dynamic>> getRoute(String destination) {
    // Normalize string
    String key = destination.toLowerCase();
    
    // Simple fuzzy matching or direct lookup
    if (key.contains("library")) return routes["library"]!;
    if (key.contains("admin")) return routes["admin block"]!;
    if (key.contains("cs 102") || key.contains("cs one zero two")) return routes["cs 102"]!;
    if (key.contains("s7") || key.contains("s seven")) return routes["s7 cs"]!;

    // Default generic route if not found but valid
    return [
      {"action": "GO STRAIGHT", "description": "Walk straight towards $destination", "direction": "up", "duration": 3},
      {"action": "ARRIVED", "description": "You have reached $destination", "direction": "stop", "duration": 2},
    ];
  }
}
