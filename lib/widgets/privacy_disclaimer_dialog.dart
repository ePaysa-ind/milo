// lib/widgets/privacy_disclaimer_dialog.dart
import 'package:flutter/material.dart';
import 'package:milo/theme/app_theme.dart';
import 'package:milo/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivacyDisclaimerDialog extends StatefulWidget {
  final Function() onAccept;
  final Function() onDecline;
  final bool showRememberChoice;

  const PrivacyDisclaimerDialog({
    Key? key,
    required this.onAccept,
    required this.onDecline,
    this.showRememberChoice = true,
  }) : super(key: key);

  // Static method to check if user has already consented
  static Future<bool> hasUserConsented() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('ai_privacy_consent') ?? false;
    } catch (e) {
      Logger.error('PrivacyDialog', 'Error checking privacy consent: $e');
      return false; // Default to false if there's an error
    }
  }

  // Static method to save user consent
  static Future<void> saveUserConsent(bool consented) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('ai_privacy_consent', consented);
      Logger.info('PrivacyDialog', 'User AI privacy consent saved: $consented');
    } catch (e) {
      Logger.error('PrivacyDialog', 'Error saving privacy consent: $e');
    }
  }

  // Static method to show the dialog
  static Future<bool> show(BuildContext context) async {
    // First check if user has already consented
    final hasConsented = await hasUserConsented();
    if (hasConsented) {
      return true;
    }

    // Otherwise show the dialog
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrivacyDisclaimerDialog(
        onAccept: () {
          Navigator.of(context).pop(true);
        },
        onDecline: () {
          Navigator.of(context).pop(false);
        },
      ),
    );

    return result ?? false;
  }

  @override
  State<PrivacyDisclaimerDialog> createState() => _PrivacyDisclaimerDialogState();
}

class _PrivacyDisclaimerDialogState extends State<PrivacyDisclaimerDialog> {
  bool _rememberChoice = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Privacy Notice',
        style: TextStyle(
          color: AppTheme.textColor,
          fontSize: AppTheme.fontSizeLarge,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To generate stories from your memories, Milo will:',
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoPoint(
              icon: Icons.upload_file,
              text: 'Send your audio recording to OpenAI (third-party service)',
            ),
            _buildInfoPoint(
              icon: Icons.mic,
              text: 'Convert your speech to text using AI technology',
            ),
            _buildInfoPoint(
              icon: Icons.auto_stories,
              text: 'Generate a story based on the content of your memory',
            ),
            _buildInfoPoint(
              icon: Icons.storage,
              text: 'Store both your original recording and the AI-generated story',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.calmBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
                border: Border.all(color: AppTheme.calmBlue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📝 Important Privacy Information',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.calmBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your privacy matters to us. Please be aware that when using this feature, your audio content is processed by OpenAI, a third-party service. While we do not retain your data on their servers permanently, it may be temporarily processed there.',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      color: AppTheme.textColor,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showRememberChoice) ...[
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(
                  'Remember my choice',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppTheme.textColor,
                  ),
                ),
                value: _rememberChoice,
                onChanged: (value) {
                  setState(() {
                    _rememberChoice = value ?? false;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Logger.info('PrivacyDialog', 'User declined AI processing');
            if (_rememberChoice) {
              await PrivacyDisclaimerDialog.saveUserConsent(false);
            }
            widget.onDecline();
          },
          child: Text(
            'No, Thanks',
            style: TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: AppTheme.fontSizeMedium,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.gentleTeal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            ),
          ),
          onPressed: () async {
            Logger.info('PrivacyDialog', 'User accepted AI processing');
            if (_rememberChoice) {
              await PrivacyDisclaimerDialog.saveUserConsent(true);
            }
            widget.onAccept();
          },
          child: Text(
            'I Understand',
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoPoint({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 20,
            color: AppTheme.gentleTeal,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTheme.fontSizeSmall,
                color: AppTheme.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}