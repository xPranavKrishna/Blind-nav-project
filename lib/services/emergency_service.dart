import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EMERGENCY SERVICE
// Stores caretaker number in SharedPreferences.
// Calls the saved number via the phone dialer.
// ─────────────────────────────────────────────────────────────────────────────

class EmergencyService {
  static const String _prefKey = "caretaker_number";

  // ── Get saved number (null if not set) ───────────────────────────────────
  Future<String?> getCaretakerNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }

  // ── Save number ───────────────────────────────────────────────────────────
  Future<void> saveCaretakerNumber(String number) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, number.trim());
  }

  // ── Delete number ─────────────────────────────────────────────────────────
  Future<void> deleteCaretakerNumber() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  // ── Make emergency call ───────────────────────────────────────────────────
  // Returns true if call was launched, false if no number saved.
  Future<bool> makeEmergencyCall() async {
    final number = await getCaretakerNumber();
    if (number == null || number.isEmpty) return false;

    // Clean number: remove spaces, dashes, parentheses
    final cleanNumber = number.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    final Uri callUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      // Skip canLaunchUrl — it fails on Android for tel: without root permission
      await launchUrl(callUri, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      // Fallback: try dial intent (opens dialer without auto-calling)
      try {
        final Uri dialUri = Uri(scheme: 'tel', path: cleanNumber);
        await launchUrl(dialUri);
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}