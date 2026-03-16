class SymptomData {
  static const Map<String, Map<String, dynamic>> symptoms = {
    // RESPIRATORY (Category 1)
    'fever': {
      'icon': 'thermostat',
      'label': 'Fever',
      'color': 0xFFFF6B35,
      'category': 'Respiratory',
      'emergency': false,
      'needsTemperature': true,
    },
    'cough': {
      'icon': 'air',
      'label': 'Cough',
      'color': 0xFF4ECDC4,
      'category': 'Respiratory',
      'emergency': false,
    },
    'sore_throat': {
      'icon': 'coronavirus',
      'label': 'Sore Throat',
      'color': 0xFFFF9FF3,
      'category': 'Respiratory',
      'emergency': false,
    },
    'difficulty_breathing': {
      'icon': 'wind_power',
      'label': 'Breathing Difficulty',
      'color': 0xFFE63946,
      'category': 'Respiratory',
      'emergency': true,
    },
    'runny_nose': {
      'icon': 'water_drop',
      'label': 'Runny Nose',
      'color': 0xFF00D9FF,
      'category': 'Respiratory',
      'emergency': false,
    },
    'congestion': {
      'icon': 'blur_on',
      'label': 'Nasal Congestion',
      'color': 0xFF7B2CBF,
      'category': 'Respiratory',
      'emergency': false,
    },
    'sneezing': {
      'icon': 'ac_unit',
      'label': 'Sneezing',
      'color': 0xFF95E1D3,
      'category': 'Respiratory',
      'emergency': false,
    },

    // DIGESTIVE (Category 2)
    'nausea': {
      'icon': 'sick',
      'label': 'Nausea',
      'color': 0xFF95E1D3,
      'category': 'Digestive',
      'emergency': false,
    },
    'vomiting': {
      'icon': 'warning',
      'label': 'Vomiting',
      'color': 0xFFFF6B6B,
      'category': 'Digestive',
      'emergency': false,
    },
    'diarrhea': {
      'icon': 'emergency',
      'label': 'Diarrhea',
      'color': 0xFFFFD93D,
      'category': 'Digestive',
      'emergency': false,
    },
    'stomach_pain': {
      'icon': 'restaurant',
      'label': 'Stomach Pain',
      'color': 0xFF06FFA5,
      'category': 'Digestive',
      'emergency': false,
    },
    'loss_appetite': {
      'icon': 'no_meals',
      'label': 'Loss of Appetite',
      'color': 0xFFB5838D,
      'category': 'Digestive',
      'emergency': false,
    },
    'bloating': {
      'icon': 'fitness_center',
      'label': 'Bloating',
      'color': 0xFFFCA311,
      'category': 'Digestive',
      'emergency': false,
    },

    // NEUROLOGICAL (Category 3)
    'headache': {
      'icon': 'psychology',
      'label': 'Headache',
      'color': 0xFFFF6B6B,
      'category': 'Neurological',
      'emergency': false,
    },
    'dizziness': {
      'icon': 'refresh',
      'label': 'Dizziness',
      'color': 0xFF7B2CBF,
      'category': 'Neurological',
      'emergency': false,
    },
    'confusion': {
      'icon': 'help',
      'label': 'Confusion',
      'color': 0xFFE63946,
      'category': 'Neurological',
      'emergency': true,
    },
    'vision_changes': {
      'icon': 'visibility_off',
      'label': 'Vision Changes',
      'color': 0xFF00D9FF,
      'category': 'Neurological',
      'emergency': true,
    },

    // GENERAL (Category 4)
    'fatigue': {
      'icon': 'battery_0_bar',
      'label': 'Fatigue',
      'color': 0xFFFFD93D,
      'category': 'General',
      'emergency': false,
    },
    'body_ache': {
      'icon': 'accessibility_new',
      'label': 'Body Ache',
      'color': 0xFFFCA311,
      'category': 'General',
      'emergency': false,
    },
    'chills': {
      'icon': 'ac_unit',
      'label': 'Chills',
      'color': 0xFF4ECDC4,
      'category': 'General',
      'emergency': false,
    },
    'sweating': {
      'icon': 'water_drop',
      'label': 'Excessive Sweating',
      'color': 0xFF00D9FF,
      'category': 'General',
      'emergency': false,
    },
    'weakness': {
      'icon': 'trending_down',
      'label': 'Weakness',
      'color': 0xFFB5838D,
      'category': 'General',
      'emergency': false,
    },

    // CARDIOVASCULAR (Category 5)
    'chest_pain': {
      'icon': 'favorite_border',
      'label': 'Chest Pain',
      'color': 0xFFE63946,
      'category': 'Cardiovascular',
      'emergency': true,
    },
    'palpitations': {
      'icon': 'favorite',
      'label': 'Heart Palpitations',
      'color': 0xFFFF6B6B,
      'category': 'Cardiovascular',
      'emergency': true,
    },
    'swelling': {
      'icon': 'water',
      'label': 'Swelling',
      'color': 0xFF00D9FF,
      'category': 'Cardiovascular',
      'emergency': false,
    },

    // SKIN (Category 6)
    'rash': {
      'icon': 'healing',
      'label': 'Rash',
      'color': 0xFFFF9FF3,
      'category': 'Skin',
      'emergency': false,
    },
    'itching': {
      'icon': 'pest_control',
      'label': 'Itching',
      'color': 0xFFFFD93D,
      'category': 'Skin',
      'emergency': false,
    },

    // OTHER (Category 7)
    'joint_pain': {
      'icon': 'back_hand',
      'label': 'Joint Pain',
      'color': 0xFFFCA311,
      'category': 'Other',
      'emergency': false,
    },
    'back_pain': {
      'icon': 'airline_seat_recline_normal',
      'label': 'Back Pain',
      'color': 0xFF7B2CBF,
      'category': 'Other',
      'emergency': false,
    },
    'earache': {
      'icon': 'hearing',
      'label': 'Earache',
      'color': 0xFFFF9FF3,
      'category': 'Other',
      'emergency': false,
    },
  };

  // Condition database with matching patterns
  static const List<Map<String, dynamic>> conditions = [
    {
      'name': 'Influenza (Flu)',
      'matchingSymptoms': ['fever', 'cough', 'body_ache', 'fatigue', 'chills', 'headache'],
      'minMatches': 3,
      'severity': 'Moderate',
      'description': 'Viral infection affecting respiratory system',
      'recommendations': [
        'Rest and stay well hydrated',
        'Take fever reducers (paracetamol/ibuprofen)',
        'Isolate from others for 5-7 days',
        'Monitor temperature every 4 hours',
        'Seek medical help if symptoms worsen',
      ],
      'urgency': 'Consult doctor if symptoms persist beyond 3 days',
    },
    {
      'name': 'COVID-19',
      'matchingSymptoms': ['fever', 'cough', 'fatigue', 'body_ache', 'loss_appetite', 'difficulty_breathing'],
      'minMatches': 3,
      'severity': 'Moderate to Severe',
      'description': 'Coronavirus infection requiring testing and monitoring',
      'recommendations': [
        'Get tested for COVID-19 immediately',
        'Self-isolate completely',
        'Monitor oxygen levels if possible',
        'Rest and stay hydrated',
        'Inform close contacts',
      ],
      'urgency': 'Seek immediate care if breathing difficulty worsens',
    },
    {
      'name': 'Common Cold',
      'matchingSymptoms': ['runny_nose', 'sneezing', 'sore_throat', 'cough', 'congestion'],
      'minMatches': 2,
      'severity': 'Mild',
      'description': 'Upper respiratory viral infection',
      'recommendations': [
        'Rest and drink plenty of fluids',
        'Use saline nasal drops',
        'Take vitamin C supplements',
        'Use steam inhalation',
        'Symptoms usually resolve in 7-10 days',
      ],
      'urgency': 'Self-care sufficient, consult if symptoms worsen',
    },
    {
      'name': 'Gastroenteritis (Stomach Flu)',
      'matchingSymptoms': ['nausea', 'vomiting', 'diarrhea', 'stomach_pain', 'fever'],
      'minMatches': 2,
      'severity': 'Mild to Moderate',
      'description': 'Inflammation of stomach and intestines',
      'recommendations': [
        'Stay hydrated with ORS or electrolyte drinks',
        'Eat bland foods (BRAT diet: Banana, Rice, Applesauce, Toast)',
        'Avoid dairy and spicy foods',
        'Rest and avoid solid foods initially',
        'Wash hands frequently',
      ],
      'urgency': 'Seek medical help if severe dehydration occurs',
    },
    {
      'name': 'Migraine',
      'matchingSymptoms': ['headache', 'nausea', 'vision_changes', 'dizziness'],
      'minMatches': 2,
      'severity': 'Moderate',
      'description': 'Severe headache with neurological symptoms',
      'recommendations': [
        'Rest in a quiet, dark room',
        'Take prescribed migraine medication',
        'Apply cold compress to forehead',
        'Avoid bright lights and loud sounds',
        'Track triggers (food, stress, sleep)',
      ],
      'urgency': 'Consult neurologist if frequent episodes',
    },
    {
      'name': 'Dehydration',
      'matchingSymptoms': ['headache', 'dizziness', 'fatigue', 'weakness'],
      'minMatches': 2,
      'severity': 'Mild to Moderate',
      'description': 'Insufficient fluid intake causing symptoms',
      'recommendations': [
        'Drink 2-3 glasses of water immediately',
        'Consume ORS or electrolyte drinks',
        'Eat water-rich fruits',
        'Avoid caffeine and alcohol',
        'Rest in a cool place',
      ],
      'urgency': 'Seek medical help if unable to keep fluids down',
    },
    {
      'name': 'Allergic Reaction',
      'matchingSymptoms': ['rash', 'itching', 'sneezing', 'runny_nose', 'swelling'],
      'minMatches': 2,
      'severity': 'Mild to Severe',
      'description': 'Immune response to allergen',
      'recommendations': [
        'Identify and avoid the allergen',
        'Take antihistamine medication',
        'Apply cool compress to affected areas',
        'Avoid scratching',
        'Monitor for worsening symptoms',
      ],
      'urgency': 'Seek emergency care if difficulty breathing or severe swelling',
    },
    {
      'name': 'Cardiac Emergency',
      'matchingSymptoms': ['chest_pain', 'difficulty_breathing', 'palpitations', 'sweating'],
      'minMatches': 2,
      'severity': 'EMERGENCY',
      'description': 'Potential heart-related emergency',
      'recommendations': [
        'Call emergency services immediately',
        'Do not drive yourself to hospital',
        'Sit down and rest',
        'Loosen tight clothing',
        'Take prescribed cardiac medication if available',
      ],
      'urgency': 'CALL 108/102 IMMEDIATELY',
    },
    {
      'name': 'Anxiety/Panic Attack',
      'matchingSymptoms': ['palpitations', 'sweating', 'dizziness', 'chest_pain', 'difficulty_breathing'],
      'minMatches': 3,
      'severity': 'Moderate',
      'description': 'Anxiety-related physical symptoms',
      'recommendations': [
        'Practice deep breathing exercises',
        'Find a quiet, safe place to sit',
        'Focus on slow, controlled breathing',
        'Ground yourself (5-4-3-2-1 technique)',
        'Consider therapy or counseling',
      ],
      'urgency': 'Consult mental health professional if frequent',
    },
    {
      'name': 'Sinusitis',
      'matchingSymptoms': ['headache', 'congestion', 'facial_pain', 'runny_nose', 'fever'],
      'minMatches': 2,
      'severity': 'Mild to Moderate',
      'description': 'Inflammation of sinus cavities',
      'recommendations': [
        'Use steam inhalation 2-3 times daily',
        'Apply warm compress to face',
        'Stay well hydrated',
        'Use saline nasal spray',
        'Take decongestants if needed',
      ],
      'urgency': 'Consult ENT if symptoms persist beyond 10 days',
    },
  ];

  // Emergency symptom detection
  static bool isEmergency(Set<String> selectedSymptoms) {
    // Check for any emergency symptoms
    for (String symptom in selectedSymptoms) {
      if (symptoms[symptom]?['emergency'] == true) {
        return true;
      }
    }

    // Check for emergency combinations
    if (selectedSymptoms.contains('chest_pain') &&
        (selectedSymptoms.contains('difficulty_breathing') ||
            selectedSymptoms.contains('sweating'))) {
      return true;
    }

    if (selectedSymptoms.contains('confusion') ||
        selectedSymptoms.contains('vision_changes')) {
      return true;
    }

    return false;
  }

  // Match symptoms to conditions
  static List<Map<String, dynamic>> matchConditions(Set<String> selectedSymptoms) {
    List<Map<String, dynamic>> matches = [];

    for (var condition in conditions) {
      List<String> requiredSymptoms = List<String>.from(condition['matchingSymptoms']);
      int minMatches = condition['minMatches'];

      // Count matching symptoms
      int matchCount = 0;
      for (String symptom in selectedSymptoms) {
        if (requiredSymptoms.contains(symptom)) {
          matchCount++;
        }
      }

      // If matches meet threshold, add to results
      if (matchCount >= minMatches) {
        double matchPercentage = (matchCount / requiredSymptoms.length) * 100;

        matches.add({
          ...condition,
          'matchPercentage': matchPercentage.round(),
          'matchedSymptoms': matchCount,
        });
      }
    }

    // Sort by match percentage (highest first)
    matches.sort((a, b) => b['matchPercentage'].compareTo(a['matchPercentage']));

    return matches;
  }

  // Get symptoms by category
  static Map<String, List<String>> getSymptomsByCategory() {
    Map<String, List<String>> categorized = {};

    symptoms.forEach((key, value) {
      String category = value['category'];
      if (!categorized.containsKey(category)) {
        categorized[category] = [];
      }
      categorized[category]!.add(key);
    });

    return categorized;
  }
}