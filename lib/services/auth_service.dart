import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'app_logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign up with email and password
  Future<Map<String, dynamic>> signUpWithEmailPassword({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      AppLogger.log('🚀 AuthService: Starting signup process');

      // Create user account
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      AppLogger.log('👤 AuthService: User created successfully');

      if (user == null) {
        AppLogger.error('AuthService: User creation failed - user is null');
        return {
          'success': false,
          'message': 'Failed to create account - user is null'
        };
      }

      // Update display name
      try {
        await user.updateDisplayName(name);
        AppLogger.log('📝 AuthService: Display name updated');
      } catch (e) {
        AppLogger.warning('AuthService: Failed to update display name: $e');
        // Continue anyway, this is not critical
      }

      // Create user document in Firestore
      try {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'name': name,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'profileCompleted': false,
          'healthProfile': {
            'age': null,
            'gender': null,
            'height': null,
            'weight': null,
            'bloodGroup': null,
            'allergies': [],
            'medications': [],
          },
          'appSettings': {
            'notifications': true,
            'reminders': true,
            'dataSharing': false,
          },
        });

        AppLogger.log('💾 AuthService: User document created in Firestore');
      } catch (e) {
        AppLogger.warning('AuthService: Failed to create Firestore document: $e');
        // Continue anyway, user account was created
      }

      return {
        'success': true,
        'user': {
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
        },
        'message': 'Account created successfully!'
      };

    } on FirebaseAuthException catch (e) {
      AppLogger.error('AuthService: FirebaseAuthException - ${e.code}');
      String message = '';
      switch (e.code) {
        case 'weak-password':
          message = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists with this email.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'operation-not-allowed':
          message = 'Email/password accounts are not enabled.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = 'An error occurred. Please try again.';
      }
      return {
        'success': false,
        'message': message,
        'error': e.code
      };
    } catch (e) {
      AppLogger.error('AuthService: Unexpected error during signup: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred.',
        'error': e.toString()
      };
    }
  }

  // Sign in with email and password
  Future<Map<String, dynamic>> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.log('🚀 AuthService: Starting signin process');

      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = result.user;
      AppLogger.log('👤 AuthService: User signed in successfully');

      if (user == null) {
        AppLogger.error('AuthService: Signin failed - user is null');
        return {
          'success': false,
          'message': 'Login failed - user is null'
        };
      }

      // Update last login
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
        AppLogger.log('💾 AuthService: Last login updated');
      } catch (e) {
        AppLogger.warning('AuthService: Failed to update last login: $e');
        // Continue anyway, user is signed in
      }

      return {
        'success': true,
        'user': {
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
        },
        'message': 'Welcome back!'
      };

    } on FirebaseAuthException catch (e) {
      AppLogger.error('AuthService: FirebaseAuthException - ${e.code}');
      String message = '';
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          message = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        case 'invalid-credential':
          message = 'Invalid email or password. Please check your credentials.';
          break;
        default:
          message = 'Login failed. Please check your credentials.';
      }
      return {
        'success': false,
        'message': message,
        'error': e.code
      };
    } catch (e) {
      AppLogger.error('AuthService: Unexpected error during signin: $e');
      return {
        'success': false,
        'message': 'An unexpected error occurred.',
        'error': e.toString()
      };
    }
  }

  // Sign in with Google
  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      AppLogger.log('🚀 AuthService: Starting Google sign-in process');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        AppLogger.log('AuthService: Google sign-in cancelled by user');
        return {
          'success': false,
          'message': 'Google sign-in cancelled'
        };
      }

      AppLogger.log('👤 AuthService: Google user obtained');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;

      AppLogger.log('🔥 AuthService: Firebase user created successfully');

      if (user == null) {
        AppLogger.error('AuthService: Google sign-in failed - user is null');
        return {
          'success': false,
          'message': 'Google sign-in failed - user is null'
        };
      }

      // Handle Firestore operations
      try {
        // Check if user document exists
        DocumentSnapshot userDoc = await _firestore.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          AppLogger.log('💾 AuthService: Creating new user document for Google user');
          // Create new user document
          await _firestore.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': user.email,
            'name': user.displayName ?? 'User',
            'photoURL': user.photoURL,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'profileCompleted': false,
            'loginProvider': 'google',
            'healthProfile': {
              'age': null,
              'gender': null,
              'height': null,
              'weight': null,
              'bloodGroup': null,
              'allergies': [],
              'medications': [],
            },
            'appSettings': {
              'notifications': true,
              'reminders': true,
              'dataSharing': false,
            },
          });
        } else {
          AppLogger.log('💾 AuthService: Updating existing user last login');
          // Update last login
          await _firestore.collection('users').doc(user.uid).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        AppLogger.warning('AuthService: Firestore operation failed: $e');
        // Continue anyway, user is signed in
      }

      return {
        'success': true,
        'user': {
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
        },
        'message': 'Google sign-in successful!'
      };

    } catch (e) {
      AppLogger.error('AuthService: Google sign-in error: $e');
      return {
        'success': false,
        'message': 'Google sign-in error: ${e.toString()}',
        'error': e.toString()
      };
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      AppLogger.log('🚀 AuthService: Starting sign out process');
      await Future.wait([
        _googleSignIn.signOut(),
        _auth.signOut(),
      ]);
      AppLogger.success('AuthService: Sign out completed');
    } catch (e) {
      AppLogger.error('AuthService: Sign out error: $e');
    }
  }

  // Reset password
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      AppLogger.log('🚀 AuthService: Sending password reset email');
      await _auth.sendPasswordResetEmail(email: email);
      AppLogger.success('AuthService: Password reset email sent');
      return {
        'success': true,
        'message': 'Password reset email sent! Check your inbox.'
      };
    } on FirebaseAuthException catch (e) {
      AppLogger.error('AuthService: Password reset error - ${e.code}');
      String message = '';
      switch (e.code) {
        case 'user-not-found':
          message = 'No account found with this email.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'network-request-failed':
          message = 'Network error. Please check your connection.';
          break;
        default:
          message = 'Failed to send reset email.';
      }
      return {
        'success': false,
        'message': message,
        'error': e.code
      };
    } catch (e) {
      AppLogger.error('AuthService: Password reset unexpected error: $e');
      return {
        'success': false,
        'message': 'An error occurred. Please try again.',
        'error': e.toString()
      };
    }
  }

  // Get user profile data
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final User? user = currentUser;
      if (user != null) {
        DocumentSnapshot doc = await _firestore.collection('users').doc(user.uid).get();
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      AppLogger.error('AuthService: Error getting user profile: $e');
      return null;
    }
  }

  // Update user profile - THIS IS THE IMPORTANT FIX
  Future<bool> updateUserProfile(Map<String, dynamic> data) async {
    try {
      final User? user = currentUser;
      if (user != null) {
        // Update Firestore first
        await _firestore.collection('users').doc(user.uid).update(data);

        // If name is being updated, also update Firebase Auth displayName
        if (data.containsKey('name') && data['name'] != null) {
          await user.updateDisplayName(data['name']);
          await user.reload();
          AppLogger.success('AuthService: DisplayName updated');
        }

        AppLogger.success('AuthService: Profile updated successfully');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('AuthService: Error updating user profile: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  PHONE NUMBER AUTHENTICATION (OTP)
  // ═══════════════════════════════════════════════════════════════════════

  String? _verificationId;
  int? _resendToken;

  /// Start phone number verification — sends OTP to the given number
  Future<Map<String, dynamic>> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String message) onError,
    Function(PhoneAuthCredential credential)? onAutoVerified,
  }) async {
    try {
      AppLogger.log('📱 AuthService: Starting phone verification');

      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        forceResendingToken: _resendToken,

        // Auto-verification (Android only — auto-reads SMS)
        verificationCompleted: (PhoneAuthCredential credential) async {
          AppLogger.success('AuthService: Auto-verification completed');
          if (onAutoVerified != null) {
            onAutoVerified(credential);
          } else {
            // Auto sign-in
            await _signInWithPhoneCredential(credential);
          }
        },

        // Verification failed
        verificationFailed: (FirebaseAuthException e) {
          AppLogger.error('AuthService: Phone verification failed - ${e.code}');
          String message;
          final errorMsg = (e.message ?? '').toUpperCase();
          if (errorMsg.contains('BILLING_NOT_ENABLED') || errorMsg.contains('BILLING')) {
            message = 'Phone auth requires Firebase Blaze plan. Please upgrade in Firebase Console (it\'s free for small usage).';
          } else {
            switch (e.code) {
              case 'invalid-phone-number':
                message = 'Invalid phone number. Please include country code (e.g., +91).';
                break;
              case 'too-many-requests':
                message = 'Too many attempts. Please try again later.';
                break;
              case 'quota-exceeded':
                message = 'SMS quota exceeded. Try again tomorrow.';
                break;
              case 'app-not-authorized':
                message = 'App not authorized for phone auth. Check Firebase console.';
                break;
              default:
                message = e.message ?? 'Phone verification failed. Please try again.';
            }
          }
          onError(message);
        },

        // Code sent successfully
        codeSent: (String verificationId, int? resendToken) {
          AppLogger.log('📨 AuthService: OTP sent successfully');
          _verificationId = verificationId;
          _resendToken = resendToken;
          onCodeSent(verificationId);
        },

        // Auto-retrieval timeout
        codeAutoRetrievalTimeout: (String verificationId) {
          AppLogger.log('⏱️ AuthService: Auto-retrieval timeout');
          _verificationId = verificationId;
        },
      );

      return {'success': true, 'message': 'OTP sent successfully'};
    } catch (e) {
      AppLogger.error('AuthService: Phone verification error: $e');
      onError('Failed to send OTP. Please try again.');
      return {'success': false, 'message': 'Failed to send OTP: $e'};
    }
  }

  /// Verify OTP and sign in
  Future<Map<String, dynamic>> verifyOTPAndSignIn({
    required String otp,
    String? verificationId,
    String? userName,
  }) async {
    try {
      final vId = verificationId ?? _verificationId;
      if (vId == null) {
        return {'success': false, 'message': 'Verification session expired. Please resend OTP.'};
      }

      AppLogger.log('🔑 AuthService: Verifying OTP...');
      final credential = PhoneAuthProvider.credential(
        verificationId: vId,
        smsCode: otp,
      );

      return await _signInWithPhoneCredential(credential, userName: userName);
    } on FirebaseAuthException catch (e) {
      AppLogger.error('AuthService: OTP verification failed - ${e.code}');
      String message;
      switch (e.code) {
        case 'invalid-verification-code':
          message = 'Invalid OTP. Please check and try again.';
          break;
        case 'session-expired':
          message = 'OTP expired. Please resend.';
          break;
        default:
          message = 'Verification failed. Please try again.';
      }
      return {'success': false, 'message': message, 'error': e.code};
    } catch (e) {
      AppLogger.error('AuthService: OTP sign-in error: $e');
      return {'success': false, 'message': 'An error occurred. Please try again.'};
    }
  }

  /// Internal: sign in with phone credential and create/update Firestore doc
  Future<Map<String, dynamic>> _signInWithPhoneCredential(
    PhoneAuthCredential credential, {String? userName}
  ) async {
    try {
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;

      if (user == null) {
        return {'success': false, 'message': 'Sign-in failed.'};
      }

      AppLogger.success('AuthService: Phone user signed in successfully');

      // Set display name if provided
      if (userName != null && userName.isNotEmpty) {
        await user.updateDisplayName(userName);
      }

      // Create or update Firestore document
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await _firestore.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'phone': user.phoneNumber,
            'name': userName ?? user.displayName ?? 'User',
            'createdAt': FieldValue.serverTimestamp(),
            'lastLogin': FieldValue.serverTimestamp(),
            'profileCompleted': false,
            'loginProvider': 'phone',
            'healthProfile': {
              'age': null, 'gender': null, 'height': null,
              'weight': null, 'bloodGroup': null,
              'allergies': [], 'medications': [],
            },
            'appSettings': {
              'notifications': true, 'reminders': true, 'dataSharing': false,
            },
          });
        } else {
          await _firestore.collection('users').doc(user.uid).update({
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        AppLogger.warning('AuthService: Firestore error (non-critical): $e');
      }

      return {
        'success': true,
        'user': {'uid': user.uid, 'phone': user.phoneNumber, 'displayName': user.displayName},
        'message': 'Phone sign-in successful!',
      };
    } catch (e) {
      AppLogger.error('AuthService: Phone credential sign-in error: $e');
      return {'success': false, 'message': 'Sign-in failed: $e'};
    }
  }
}