class AccessChecker {
  static bool hasFeature(Map<String, dynamic>? enrollment, String feature) {
    if (enrollment == null) return false;
    
    final features = List<String>.from(
      enrollment['plan_features'] as List<dynamic>? ?? []
    );
    
    // If no features stored (old enrollments), grant access
    if (features.isEmpty) return true;
    
    return features.any((f) => f.toLowerCase().contains(feature.toLowerCase()));
  }
  
  static bool canAccessLiveLessons(Map<String, dynamic>? enrollment) {
    return hasFeature(enrollment, 'Live Lessons');
  }
  
  static bool canAccessRecordedLessons(Map<String, dynamic>? enrollment) {
    return hasFeature(enrollment, 'Recorded Lessons');
  }
  
  static bool canAccessNotes(Map<String, dynamic>? enrollment) {
    return hasFeature(enrollment, 'Notes & Resources');
  }
  
  static bool canAccessExamPrep(Map<String, dynamic>? enrollment) {
    return hasFeature(enrollment, 'Exam Preparation');
  }
  
  static bool canAccessMCQ(Map<String, dynamic>? enrollment) {
    return hasFeature(enrollment, 'MCQ Practice');
  }
  // Add this to AccessChecker
static bool canAccessTutoring(Map<String, dynamic>? enrollment) {
  return hasFeature(enrollment, 'One-on-One Support');
}
}