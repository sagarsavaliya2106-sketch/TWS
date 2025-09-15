import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_strings.dart';
import '../core/constants/app_text_styles.dart';
import '../core/constants/app_dimensions.dart';
import '../utils/responsive_helper.dart';

class LoginScreen extends GetView<AuthController> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.primaryGradient,
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: ResponsiveHelper.getContainerConstraints(context),
              child: SingleChildScrollView(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Form(
                  key: controller.formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppStrings.welcomeBack,
                        style: AppTextStyles.titleLargeWhite.copyWith(
                          fontSize: ResponsiveHelper.getTitleFontSize(context),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 0.25),
                      Text(
                        AppStrings.signInToContinue,
                        style: AppTextStyles.bodyMediumWhite.copyWith(
                          fontSize: ResponsiveHelper.getSubtitleFontSize(context),
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 1.25),

                      // Login Form Card
                      Container(
                        width: ResponsiveHelper.getCardWidth(context),
                        padding: ResponsiveHelper.getResponsivePadding(context),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusL),
                          boxShadow: const [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 15,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 0.75),

                            // Email Input
                            TextFormField(
                              controller: controller.emailPhoneController,
                              keyboardType: TextInputType.emailAddress,
                              style: AppTextStyles.inputText.copyWith(
                                fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.9,
                              ),
                              decoration: InputDecoration(
                                labelText: AppStrings.email,
                                labelStyle: AppTextStyles.inputLabel.copyWith(
                                  fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.85,
                                ),
                                prefixIcon: Icon(
                                  Icons.email,
                                  size: ResponsiveHelper.getIconSize(context),
                                  color: AppColors.primary,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.isMobile(context) ? 12 : 16,
                                  vertical: ResponsiveHelper.isMobile(context) ? 16 : 20,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return AppStrings.pleaseEnterEmail;
                                }
                                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                  return AppStrings.pleaseEnterValidEmail;
                                }
                                return null;
                              },
                            ),
                            
                            Container(
                              margin: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.getVerticalSpacing(context) * 0.75,
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Divider(
                                      thickness: 1,
                                      color: AppColors.divider,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: ResponsiveHelper.getVerticalSpacing(context) * 0.5,
                                    ),
                                    child: Text(
                                      AppStrings.or,
                                      style: AppTextStyles.labelMedium.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: ResponsiveHelper.getSubtitleFontSize(context) * 0.8,
                                      ),
                                    ),
                                  ),
                                  const Expanded(
                                    child: Divider(
                                      thickness: 1,
                                      color: AppColors.divider,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Phone Input
                            TextFormField(
                              controller: controller.phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: AppTextStyles.inputText.copyWith(
                                fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.9,
                              ),
                              decoration: InputDecoration(
                                labelText: AppStrings.phoneNumber,
                                labelStyle: AppTextStyles.inputLabel.copyWith(
                                  fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.85,
                                ),
                                prefixIcon: Icon(
                                  Icons.phone,
                                  size: ResponsiveHelper.getIconSize(context),
                                  color: AppColors.primary,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                                  borderSide: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.isMobile(context) ? 12 : 16,
                                  vertical: ResponsiveHelper.isMobile(context) ? 16 : 20,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return AppStrings.pleaseEnterPhone;
                                }
                                if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                                  return AppStrings.phoneOnlyDigits;
                                }
                                if (value.length != 10) {
                                  return AppStrings.pleaseEnterValidPhone;
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 1.5),

                            // Password Input
                            // Obx(() => TextFormField(
                            //   controller: controller.passwordController,
                            //   obscureText: !controller.isPasswordVisible.value,
                            //   style: AppTextStyles.inputText.copyWith(
                            //     fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.9,
                            //   ),
                            //   decoration: InputDecoration(
                            //     labelText: AppStrings.password,
                            //     labelStyle: AppTextStyles.inputLabel.copyWith(
                            //       fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.85,
                            //     ),
                            //     prefixIcon: Icon(
                            //       Icons.lock,
                            //       size: ResponsiveHelper.getIconSize(context),
                            //       color: AppColors.primary,
                            //     ),
                            //     suffixIcon: IconButton(
                            //       icon: Icon(
                            //         controller.isPasswordVisible.value
                            //             ? Icons.visibility
                            //             : Icons.visibility_off,
                            //         size: ResponsiveHelper.getIconSize(context),
                            //         color: AppColors.textSecondary,
                            //       ),
                            //       onPressed: controller.togglePasswordVisibility,
                            //     ),
                            //     border: OutlineInputBorder(
                            //       borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                            //     ),
                            //     focusedBorder: OutlineInputBorder(
                            //       borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                            //       borderSide: const BorderSide(
                            //         color: AppColors.primary,
                            //       ),
                            //     ),
                            //     contentPadding: EdgeInsets.symmetric(
                            //       horizontal: ResponsiveHelper.isMobile(context) ? 12 : 16,
                            //       vertical: ResponsiveHelper.isMobile(context) ? 16 : 20,
                            //     ),
                            //   ),
                            //   validator: (value) {
                            //     if (value == null || value.isEmpty) {
                            //       return AppStrings.pleaseEnterPassword;
                            //     }
                            //     String pattern = r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{8,}$';
                            //     RegExp regex = RegExp(pattern);
                            //     if (!regex.hasMatch(value)) {
                            //       return AppStrings.passwordRequirements;
                            //     }
                            //     return null;
                            //   },
                            // )),
                            // SizedBox(height: ResponsiveHelper.getVerticalSpacing(context)),

                            // Login Button
                            SizedBox(
                              width: double.infinity,
                              height: ResponsiveHelper.getButtonHeight(context),
                              child: Obx(() => ElevatedButton(
                                onPressed: controller.isLoading.value ? null : controller.handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppDimensions.radiusM),
                                  ),
                                  elevation: AppDimensions.cardElevation,
                                ),
                                child: controller.isLoading.value
                                    ? const CircularProgressIndicator(
                                        color: AppColors.textWhite,
                                      )
                                    : Text(
                                        AppStrings.signIn,
                                        style: AppTextStyles.buttonText.copyWith(
                                          fontSize: ResponsiveHelper.getBodyFontSize(context),
                                        ),
                                      ),
                              )),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: ResponsiveHelper.getVerticalSpacing(context) * 0.75),

                      // Forgot Password
                      TextButton(
                        onPressed: () {
                          // Add forgot password functionality
                        },
                        child: Text(
                          AppStrings.forgotPassword,
                          style: AppTextStyles.linkText.copyWith(
                            color: AppColors.textWhite,
                            fontSize: ResponsiveHelper.getSubtitleFontSize(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
