import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';

/// A collection of UI components specifically designed for elderly users (55+)
/// with accessibility considerations including:
/// - Large touch targets
/// - High contrast
/// - Clear visual feedback
/// - Consistent haptic feedback
/// - Simple interaction patterns
/// - Descriptive semantics for screen readers

/// Large, accessible button with high contrast and clear feedback
class AccessibleButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isProminent;
  final bool enableHapticFeedback;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? textColor;

  const AccessibleButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isProminent = false,
    this.enableHapticFeedback = true,
    this.fullWidth = false,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Base styles from theme
    final buttonStyle = isProminent
        ? ElevatedButton.styleFrom(
      backgroundColor: backgroundColor ?? AppTheme.gentleTeal,
      foregroundColor: textColor ?? Colors.black,
      elevation: 6,
      shadowColor: (backgroundColor ?? AppTheme.gentleTeal).withOpacity(0.4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingMedium - 4,
      ),
      minimumSize: Size(
        fullWidth ? double.infinity : AppTheme.buttonMinWidth,
        AppTheme.buttonMinHeight + 8,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        side: BorderSide(
          color: (backgroundColor ?? AppTheme.gentleTeal).withOpacity(0.3),
          width: 1.5,
        ),
      ),
    )
        : OutlinedButton.styleFrom(
      foregroundColor: backgroundColor ?? AppTheme.gentleTeal,
      side: BorderSide(
        color: (backgroundColor ?? AppTheme.gentleTeal),
        width: 2.0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingMedium - 4,
      ),
      minimumSize: Size(
        fullWidth ? double.infinity : AppTheme.buttonMinWidth,
        AppTheme.buttonMinHeight + 4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
    );

    // Text style based on prominence level
    final textStyle = TextStyle(
      fontFamily: AppTheme.primaryFontFamily,
      fontSize: AppTheme.fontSizeMedium,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: isProminent
          ? textColor ?? Colors.black
          : backgroundColor ?? AppTheme.gentleTeal,
    );

    // Decide which button type to use
    final button = isProminent
        ? ElevatedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: _buildButtonContent(textStyle),
    )
        : OutlinedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: _buildButtonContent(textStyle),
    );

    // Wrap with semantic information for screen readers
    return Semantics(
      button: true,
      enabled: true,
      label: label,
      onTap: () {
        if (enableHapticFeedback) {
          HapticFeedback.mediumImpact();
        }
        onPressed();
      },
      child: button,
    );
  }

  Widget _buildButtonContent(TextStyle textStyle) {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: AppTheme.iconSizeSmall,
            color: textStyle.color,
          ),
          const SizedBox(width: AppTheme.spacingSmall / 2),
          Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else {
      return Text(
        label,
        style: textStyle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
  }
}

/// Icon button with large touch target and clear visual feedback
class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final bool enableHapticFeedback;
  final Color? iconColor;
  final double size;
  final bool hasBorder;

  const AccessibleIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.enableHapticFeedback = true,
    this.iconColor,
    this.size = AppTheme.iconSizeMedium,
    this.hasBorder = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: semanticLabel,
      onTap: () {
        if (enableHapticFeedback) {
          HapticFeedback.mediumImpact();
        }
        onPressed();
      },
      child: Container(
        decoration: hasBorder
            ? BoxDecoration(
          border: Border.all(
            color: (iconColor ?? AppTheme.textColor).withOpacity(0.3),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
        )
            : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (enableHapticFeedback) {
                HapticFeedback.mediumImpact();
              }
              onPressed();
            },
            customBorder: const CircleBorder(),
            highlightColor: (iconColor ?? AppTheme.textColor).withOpacity(0.2),
            splashColor: (iconColor ?? AppTheme.textColor).withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingSmall),
              child: Icon(
                icon,
                color: iconColor ?? AppTheme.textColor,
                size: size,
                semanticLabel: semanticLabel,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card with clear borders and high contrast content for better visibility
class AccessibleCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double elevation;
  final EdgeInsetsGeometry padding;
  final bool enableHapticFeedback;
  final BorderRadius? borderRadius;
  final String? semanticLabel;

  const AccessibleCard({
    Key? key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.elevation = 4.0,
    this.padding = const EdgeInsets.all(AppTheme.spacingMedium),
    this.enableHapticFeedback = true,
    this.borderRadius,
    this.semanticLabel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cardWidget = Card(
      color: backgroundColor ?? AppTheme.cardColor,
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.borderRadiusMedium),
        side: BorderSide(
          color: Colors.white.withOpacity(0.1),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap != null) {
      return Semantics(
        button: true,
        enabled: true,
        label: semanticLabel,
        onTap: () {
          if (enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }
          onTap!();
        },
        child: InkWell(
          onTap: () {
            if (enableHapticFeedback) {
              HapticFeedback.mediumImpact();
            }
            onTap!();
          },
          borderRadius: borderRadius ?? BorderRadius.circular(AppTheme.borderRadiusMedium),
          highlightColor: Colors.white.withOpacity(0.05),
          splashColor: Colors.white.withOpacity(0.03),
          child: cardWidget,
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      child: cardWidget,
    );
  }
}

/// Switch with enhanced visibility, larger touch target, and descriptive labels
class AccessibleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;
  final bool enableHapticFeedback;
  final Color? activeColor;
  final Color? inactiveColor;

  const AccessibleSwitch({
    Key? key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.enableHapticFeedback = true,
    this.activeColor,
    this.inactiveColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      hint: description,
      child: GestureDetector(
        onTap: () {
          if (enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }
          onChanged(!value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacingSmall / 2,
            horizontal: AppTheme.spacingSmall / 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            color: AppTheme.surfaceColor,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textColor,
                        height: 1.3,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          description!,
                          style: TextStyle(
                            fontFamily: AppTheme.primaryFontFamily,
                            fontSize: AppTheme.fontSizeSmall,
                            color: AppTheme.textSecondaryColor,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 1.3, // 30% larger for easier targeting
                child: Switch(
                  value: value,
                  onChanged: (newValue) {
                    if (enableHapticFeedback) {
                      HapticFeedback.mediumImpact();
                    }
                    onChanged(newValue);
                  },
                  activeColor: activeColor ?? AppTheme.gentleTeal,
                  activeTrackColor: (activeColor ?? AppTheme.gentleTeal).withOpacity(0.5),
                  inactiveThumbColor: inactiveColor ?? Colors.grey[400],
                  inactiveTrackColor: (inactiveColor ?? Colors.grey[600])?.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TextField with larger font size, clear borders, and high contrast colors
class AccessibleTextField extends StatelessWidget {
  final String label;
  final String? placeholder;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final TextInputType keyboardType;
  final bool obscureText;
  final String? errorText;
  final int? maxLines;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixIconPressed;
  final String? suffixIconSemanticLabel;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enableHapticFeedback;

  const AccessibleTextField({
    Key? key,
    required this.label,
    this.placeholder,
    required this.controller,
    this.onChanged,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.errorText,
    this.maxLines = 1,
    this.prefixIcon,
    this.suffixIcon,
    this.onSuffixIconPressed,
    this.suffixIconSemanticLabel,
    this.autofocus = false,
    this.focusNode,
    this.enableHapticFeedback = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Field label outside the TextField for better visibility
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacingSmall / 2,
            bottom: AppTheme.spacingSmall / 2,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeMedium,
              fontWeight: FontWeight.w600,
              color: AppTheme.textColor,
            ),
          ),
        ),
        TextField(
          controller: controller,
          onChanged: (value) {
            if (enableHapticFeedback) {
              HapticFeedback.selectionClick();
            }
            if (onChanged != null) {
              onChanged!(value);
            }
          },
          style: TextStyle(
            fontFamily: AppTheme.primaryFontFamily,
            fontSize: AppTheme.fontSizeMedium,
            color: AppTheme.textColor,
            height: 1.3,
          ),
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: maxLines,
          autofocus: autofocus,
          focusNode: focusNode,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeMedium,
              color: AppTheme.textColor.withOpacity(0.5),
            ),
            errorText: errorText,
            errorStyle: TextStyle(
              fontFamily: AppTheme.primaryFontFamily,
              fontSize: AppTheme.fontSizeSmall,
              color: AppTheme.errorColor,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: AppTheme.surfaceColor,
            contentPadding: const EdgeInsets.all(AppTheme.spacingMedium),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              borderSide: BorderSide(
                color: AppTheme.gentleTeal.withOpacity(0.5),
                width: 2.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              borderSide: BorderSide(
                color: AppTheme.gentleTeal.withOpacity(0.5),
                width: 2.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              borderSide: BorderSide(
                color: AppTheme.gentleTeal,
                width: 3.0,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
              borderSide: BorderSide(
                color: AppTheme.errorColor,
                width: 2.0,
              ),
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
              prefixIcon,
              color: AppTheme.textColor.withOpacity(0.7),
              size: AppTheme.iconSizeSmall,
            )
                : null,
            suffixIcon: suffixIcon != null
                ? IconButton(
              icon: Icon(
                suffixIcon,
                color: AppTheme.gentleTeal,
                size: AppTheme.iconSizeSmall,
              ),
              onPressed: () {
                if (enableHapticFeedback) {
                  HapticFeedback.mediumImpact();
                }
                if (onSuffixIconPressed != null) {
                  onSuffixIconPressed!();
                }
              },
              padding: const EdgeInsets.all(12.0),
              tooltip: suffixIconSemanticLabel,
            )
                : null,
          ),
        ),
      ],
    );
  }
}

/// List item with large touch target and clear visual hierarchy
class AccessibleListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final Widget? leadingWidget;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool enableHapticFeedback;
  final bool isSelected;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;

  const AccessibleListItem({
    Key? key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leadingWidget,
    this.trailing,
    required this.onTap,
    this.enableHapticFeedback = true,
    this.isSelected = false,
    this.backgroundColor,
    this.selectedBackgroundColor,
  }) : assert(leadingIcon == null || leadingWidget == null,
  'Cannot provide both leadingIcon and leadingWidget'),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: true,
      label: title + (subtitle != null ? ', ' + subtitle! : ''),
      selected: isSelected,
      onTap: () {
        if (enableHapticFeedback) {
          HapticFeedback.mediumImpact();
        }
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedBackgroundColor ?? AppTheme.gentleTeal.withOpacity(0.15)
              : backgroundColor ?? AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          border: Border.all(
            color: isSelected
                ? AppTheme.gentleTeal
                : Colors.white.withOpacity(0.05),
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (enableHapticFeedback) {
                HapticFeedback.mediumImpact();
              }
              onTap();
            },
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            highlightColor: AppTheme.gentleTeal.withOpacity(0.1),
            splashColor: AppTheme.gentleTeal.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingMedium - 4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Leading icon or widget
                  if (leadingIcon != null)
                    Container(
                      width: AppTheme.iconSizeMedium + 16,
                      height: AppTheme.iconSizeMedium + 16,
                      margin: const EdgeInsets.only(right: AppTheme.spacingSmall),
                      decoration: BoxDecoration(
                        color: AppTheme.gentleTeal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusCircular),
                      ),
                      child: Center(
                        child: Icon(
                          leadingIcon,
                          size: AppTheme.iconSizeSmall,
                          color: AppTheme.gentleTeal,
                        ),
                      ),
                    )
                  else if (leadingWidget != null)
                    Padding(
                      padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
                      child: leadingWidget,
                    ),

                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: AppTheme.primaryFontFamily,
                            fontSize: AppTheme.fontSizeMedium,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? AppTheme.gentleTeal
                                : AppTheme.textColor,
                            height: 1.3,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontFamily: AppTheme.primaryFontFamily,
                                fontSize: AppTheme.fontSizeSmall,
                                color: AppTheme.textSecondaryColor,
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Trailing widget (usually an icon or button)
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section header with clear labeling
class AccessibleSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment alignment;

  const AccessibleSectionHeader({
    Key? key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(
      vertical: AppTheme.spacingSmall,
      horizontal: AppTheme.spacingSmall,
    ),
    this.alignment = CrossAxisAlignment.start,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: alignment,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTheme.primaryFontFamily,
                      fontSize: AppTheme.fontSizeLarge,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textColor,
                      height: 1.3,
                      letterSpacing: 0.25,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: AppTheme.primaryFontFamily,
                          fontSize: AppTheme.fontSizeSmall,
                          color: AppTheme.textSecondaryColor,
                          height: 1.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Alert or notification banner with clear visual importance and status
class AccessibleAlertBanner extends StatelessWidget {
  final String message;
  final String? details;
  final IconData icon;
  final AlertType type;
  final VoidCallback? onDismiss;
  final VoidCallback? onActionPressed;
  final String? actionLabel;
  final EdgeInsetsGeometry margin;

  const AccessibleAlertBanner({
    Key? key,
    required this.message,
    this.details,
    required this.icon,
    required this.type,
    this.onDismiss,
    this.onActionPressed,
    this.actionLabel,
    this.margin = const EdgeInsets.symmetric(
      vertical: AppTheme.spacingSmall,
      horizontal: AppTheme.spacingSmall,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine colors based on type
    Color backgroundColor;
    Color iconColor;
    Color borderColor;

    switch (type) {
      case AlertType.success:
        backgroundColor = AppTheme.successColor.withOpacity(0.15);
        iconColor = AppTheme.successColor;
        borderColor = AppTheme.successColor;
        break;
      case AlertType.warning:
        backgroundColor = AppTheme.warningColor.withOpacity(0.15);
        iconColor = AppTheme.warningColor;
        borderColor = AppTheme.warningColor;
        break;
      case AlertType.error:
        backgroundColor = AppTheme.errorColor.withOpacity(0.15);
        iconColor = AppTheme.errorColor;
        borderColor = AppTheme.errorColor;
        break;
      case AlertType.info:
      default:
        backgroundColor = AppTheme.calmBlue.withOpacity(0.15);
        iconColor = AppTheme.calmBlue;
        borderColor = AppTheme.calmBlue;
        break;
    }

    return Semantics(
      container: true,
      liveRegion: true, // Important for screen readers to announce
      label: "${_getAlertTypeString(type)} alert: $message",
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          border: Border.all(
            color: borderColor,
            width: 2.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Padding(
                padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: AppTheme.iconSizeSmall,
                ),
              ),

              // Message and optional details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textColor,
                        height: 1.3,
                      ),
                    ),
                    if (details != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          details!,
                          style: TextStyle(
                            fontFamily: AppTheme.primaryFontFamily,
                            fontSize: AppTheme.fontSizeSmall,
                            color: AppTheme.textSecondaryColor,
                            height: 1.3,
                          ),
                        ),
                      ),

                    // Optional action button
                    if (actionLabel != null && onActionPressed != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
                        child: AccessibleButton(
                          label: actionLabel!,
                          onPressed: onActionPressed!,
                          backgroundColor: borderColor,
                          textColor: type == AlertType.warning ? Colors.black : Colors.white,
                        ),
                      ),
                  ],
                ),
              ),

              // Optional dismiss button
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                  color: AppTheme.textColor.withOpacity(0.7),
                  tooltip: 'Dismiss',
                  padding: const EdgeInsets.all(8.0),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getAlertTypeString(AlertType type) {
    switch (type) {
      case AlertType.success:
        return 'Success';
      case AlertType.warning:
        return 'Warning';
      case AlertType.error:
        return 'Error';
      case AlertType.info:
      default:
        return 'Information';
    }
  }
}

/// Radio button group with large touch targets and clear labeling
class AccessibleRadioGroup<T> extends StatelessWidget {
  final String groupLabel;
  final List<AccessibleRadioOption<T>> options;
  final T selectedValue;
  final ValueChanged<T?> onChanged;
  final bool enableHapticFeedback;
  final EdgeInsetsGeometry padding;

  const AccessibleRadioGroup({
    Key? key,
    required this.groupLabel,
    required this.options,
    required this.selectedValue,
    required this.onChanged,
    this.enableHapticFeedback = true,
    this.padding = const EdgeInsets.symmetric(
      vertical: AppTheme.spacingSmall,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: groupLabel,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group label
            Padding(
              padding: const EdgeInsets.only(
                left: AppTheme.spacingSmall / 2,
                bottom: AppTheme.spacingSmall,
              ),
              child: Text(
                groupLabel,
                style: TextStyle(
                  fontFamily: AppTheme.primaryFontFamily,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textColor,
                ),
              ),
            ),

            // Radio options
            ...options.map((option) => _buildRadioOption(option, context)),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioOption(AccessibleRadioOption<T> option, BuildContext context) {
    final isSelected = selectedValue == option.value;

    return Semantics(
      label: option.label,
      hint: option.description,
      checked: isSelected,
      child: GestureDetector(
        onTap: () {
          if (enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }
          onChanged(option.value);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8.0),
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacingSmall,
            horizontal: AppTheme.spacingSmall,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            color: isSelected
                ? AppTheme.gentleTeal.withOpacity(0.15)
                : AppTheme.surfaceColor,
            border: Border.all(
              color: isSelected
                  ? AppTheme.gentleTeal
                  : Colors.white.withOpacity(0.1),
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Radio button
              Transform.scale(
                scale: 1.3, // 30% larger for easier targeting
                child: Radio<T>(
                  value: option.value,
                  groupValue: selectedValue,
                  onChanged: (value) {
                    if (enableHapticFeedback) {
                      HapticFeedback.mediumImpact();
                    }
                    onChanged(value);
                  },
                  activeColor: AppTheme.gentleTeal,
                ),
              ),

              const SizedBox(width: 8.0),

              // Label and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.gentleTeal
                            : AppTheme.textColor,
                        height: 1.3,
                      ),
                    ),
                    if (option.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          option.description!,
                          style: TextStyle(
                            fontFamily: AppTheme.primaryFontFamily,
                            fontSize: AppTheme.fontSizeSmall,
                            color: AppTheme.textSecondaryColor,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Data class for radio options
class AccessibleRadioOption<T> {
  final String label;
  final String? description;
  final T value;

  const AccessibleRadioOption({
    required this.label,
    this.description,
    required this.value,
  });
}

/// Checkbox with large touch target and clear visual state
class AccessibleCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final String? description;
  final bool enableHapticFeedback;
  final Color? activeColor;

  const AccessibleCheckbox({
    Key? key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.description,
    this.enableHapticFeedback = true,
    this.activeColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      label: label,
      hint: description,
      child: GestureDetector(
        onTap: () {
          if (enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }
          onChanged(!value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacingSmall / 2,
            horizontal: AppTheme.spacingSmall / 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
            color: value
                ? (activeColor ?? AppTheme.gentleTeal).withOpacity(0.15)
                : AppTheme.surfaceColor,
            border: Border.all(
              color: value
                  ? (activeColor ?? AppTheme.gentleTeal)
                  : Colors.white.withOpacity(0.1),
              width: value ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Checkbox
              Transform.scale(
                scale: 1.3, // 30% larger for easier targeting
                child: Checkbox(
                  value: value,
                  onChanged: (newValue) {
                    if (enableHapticFeedback) {
                      HapticFeedback.mediumImpact();
                    }
                    onChanged(newValue ?? false);
                  },
                  activeColor: activeColor ?? AppTheme.gentleTeal,
                  checkColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                ),
              ),

              const SizedBox(width: 8.0),

              // Label and description
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                        color: value
                            ? (activeColor ?? AppTheme.gentleTeal)
                            : AppTheme.textColor,
                        height: 1.3,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          description!,
                          style: TextStyle(
                            fontFamily: AppTheme.primaryFontFamily,
                            fontSize: AppTheme.fontSizeSmall,
                            color: AppTheme.textSecondaryColor,
                            height: 1.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom action bar with large, clear buttons
class AccessibleBottomActionBar extends StatelessWidget {
  final List<AccessibleBottomAction> actions;
  final Color backgroundColor;
  final double height;
  final EdgeInsets padding;

  const AccessibleBottomActionBar({
    Key? key,
    required this.actions,
    this.backgroundColor = AppTheme.backgroundColor,
    this.height = 80.0,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.spacingMedium,
      vertical: AppTheme.spacingSmall,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: padding,
      child: Row(
        mainAxisAlignment: actions.length > 1
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: actions.map((action) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingSmall / 2,
              ),
              child: AccessibleButton(
                label: action.label,
                onPressed: action.onPressed,
                icon: action.icon,
                isProminent: action.isProminent,
                backgroundColor: action.backgroundColor,
                textColor: action.textColor,
                fullWidth: true,
                enableHapticFeedback: action.enableHapticFeedback,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Data class for bottom action
class AccessibleBottomAction {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isProminent;
  final Color? backgroundColor;
  final Color? textColor;
  final bool enableHapticFeedback;

  const AccessibleBottomAction({
    required this.label,
    required this.onPressed,
    this.icon,
    this.isProminent = true,
    this.backgroundColor,
    this.textColor,
    this.enableHapticFeedback = true,
  });
}

/// Segmented button group with high contrast and clear states
class AccessibleSegmentedButtons<T> extends StatelessWidget {
  final List<AccessibleSegmentOption<T>> options;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final bool enableHapticFeedback;
  final EdgeInsetsGeometry margin;

  const AccessibleSegmentedButtons({
    Key? key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.enableHapticFeedback = true,
    this.margin = const EdgeInsets.symmetric(
      vertical: AppTheme.spacingSmall,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        margin: margin,
        height: AppTheme.buttonMinHeight + 4,
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        child: Row(
          children: options.map((option) {
            final isSelected = option.value == selectedValue;
            final index = options.indexOf(option);
            final isFirst = index == 0;
            final isLast = index == options.length - 1;

            // Determine border radius based on position
            final borderRadius = BorderRadius.only(
              topLeft: isFirst ? const Radius.circular(AppTheme.borderRadiusMedium - 1.5) : Radius.zero,
              bottomLeft: isFirst ? const Radius.circular(AppTheme.borderRadiusMedium - 1.5) : Radius.zero,
              topRight: isLast ? const Radius.circular(AppTheme.borderRadiusMedium - 1.5) : Radius.zero,
              bottomRight: isLast ? const Radius.circular(AppTheme.borderRadiusMedium - 1.5) : Radius.zero,
            );

            return Expanded(
              child: Semantics(
                button: true,
                label: option.label,
                selected: isSelected,
                onTap: () {
                  if (enableHapticFeedback) {
                    HapticFeedback.mediumImpact();
                  }
                  onSelected(option.value);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.gentleTeal
                        : Colors.transparent,
                    borderRadius: borderRadius,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (enableHapticFeedback) {
                          HapticFeedback.mediumImpact();
                        }
                        onSelected(option.value);
                      },
                      borderRadius: borderRadius,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (option.icon != null) ...[
                              Icon(
                                option.icon,
                                size: AppTheme.iconSizeSmall - 4,
                                color: isSelected ? Colors.black : AppTheme.textColor,
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              option.label,
                              style: TextStyle(
                                fontFamily: AppTheme.primaryFontFamily,
                                fontSize: AppTheme.fontSizeSmall,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.black : AppTheme.textColor,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Data class for segmented button options
class AccessibleSegmentOption<T> {
  final String label;
  final IconData? icon;
  final T value;

  const AccessibleSegmentOption({
    required this.label,
    this.icon,
    required this.value,
  });
}

/// Tab navigation with large text and clear visual indicators
class AccessibleTabBar extends StatelessWidget {
  final List<AccessibleTabOption> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool enableHapticFeedback;
  final double height;
  final EdgeInsets padding;

  const AccessibleTabBar({
    Key? key,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    this.enableHapticFeedback = true,
    this.height = 64,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.spacingMedium,
      vertical: AppTheme.spacingSmall / 2,
    ),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.elevationColors[8],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = index == selectedIndex;

          return Expanded(
            child: Semantics(
              selected: isSelected,
              button: true,
              label: tab.label,
              onTap: () {
                if (enableHapticFeedback) {
                  HapticFeedback.mediumImpact();
                }
                onTabSelected(index);
              },
              child: InkWell(
                onTap: () {
                  if (enableHapticFeedback) {
                    HapticFeedback.mediumImpact();
                  }
                  onTabSelected(index);
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Icon(
                      tab.icon,
                      color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor.withOpacity(0.7),
                      size: AppTheme.iconSizeSmall,
                    ),

                    const SizedBox(height: 4),

                    // Label
                    Text(
                      tab.label,
                      style: TextStyle(
                        fontFamily: AppTheme.primaryFontFamily,
                        fontSize: AppTheme.fontSizeSmall,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? AppTheme.gentleTeal : AppTheme.textColor.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Selection indicator
                    if (isSelected)
                      Container(
                        height: 3,
                        width: 30,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.gentleTeal,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Data class for tab options
class AccessibleTabOption {
  final String label;
  final IconData icon;

  const AccessibleTabOption({
    required this.label,
    required this.icon,
  });
}

/// Alert type enum
enum AlertType {
  info,
  success,
  warning,
  error,
}

/// Usage examples:
///
/// Example for AccessibleButton:
/// ```dart
/// AccessibleButton(
///   label: 'Continue',
///   onPressed: () {
///     // Handle button press
///   },
///   icon: Icons.arrow_forward,
///   isProminent: true,
/// )
/// ```
///
/// Example for AccessibleTextField:
/// ```dart
/// AccessibleTextField(
///   label: 'Email Address',
///   placeholder: 'Enter your email',
///   controller: emailController,
///   keyboardType: TextInputType.emailAddress,
///   prefixIcon: Icons.email,
/// )
/// ```
///
/// Example for AccessibleCheckbox:
/// ```dart
/// AccessibleCheckbox(
///   value: isChecked,
///   onChanged: (value) {
///     setState(() {
///       isChecked = value;
///     });
///   },
///   label: 'Enable notifications',
///   description: 'Receive daily reminders and alerts',
/// )
/// ```
///
/// Example for AccessibleBottomActionBar:
/// ```dart
/// AccessibleBottomActionBar(
///   actions: [
///     AccessibleBottomAction(
///       label: 'Cancel',
///       onPressed: () {
///         Navigator.pop(context);
///       },
///       isProminent: false,
///     ),
///     AccessibleBottomAction(
///       label: 'Save',
///       onPressed: () {
///         // Save functionality
///       },
///       icon: Icons.check,
///     ),
///   ],
/// )
/// ```