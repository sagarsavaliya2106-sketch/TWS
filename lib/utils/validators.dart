bool isValidMobile(String s) {
  // Remove spaces, hyphens, etc.
  final cleaned = s.replaceAll(RegExp(r'\D'), '');

  // Must be exactly 10 digits
  if (cleaned.length != 10) return false;

  // Must contain only numbers
  if (int.tryParse(cleaned) == null) return false;

  // OPTIONAL strict rule (uncomment if needed)
  // if (!['6', '7', '8', '9'].contains(cleaned[0])) return false;

  return true;
}
