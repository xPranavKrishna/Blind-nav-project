import 'package:url_launcher/url_launcher.dart';

class EmergencyService {
  // Hardcoded caretaker number for demo
  final String caretakerNumber = "+919876543210"; 

  Future<void> makeEmergencyCall() async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: caretakerNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      throw 'Could not launch $launchUri';
    }
  }
}
