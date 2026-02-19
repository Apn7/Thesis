import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/constants.dart';
import '../../core/navigation/app_routes.dart';
import '../../services/voice_navigation_service.dart';
import '../widgets/accessible_action_button.dart';
import '../widgets/voice_indicator.dart';

/// Home screen with voice-first navigation
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VoiceNavigationService _voiceService = VoiceNavigationService.instance;
  bool _isInitialized = false;
  
  // TCP Server State
  ServerSocket? _serverSocket;
  Socket? _connectedClient;
  String _connectionStatus = 'Initializing Server...';
  String _latestAlert = '';
  String _deviceIpAddress = 'Detecting...';
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupNavigationCallback();
    _startTcpServer();
  }
  
  @override
  void dispose() {
    _stopTcpServer();
    super.dispose();
  }
  
  /// Starts the TCP server to listen for Raspberry Pi messages
  Future<void> _startTcpServer() async {
    try {
      // Get device IP address for display
      await _getDeviceIpAddress();
      
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 4444);
      print('>> TCP SERVER LISTENING on Port 4444');
      print('>> Device IP: $_deviceIpAddress');
      
      setState(() {
        _connectionStatus = 'Waiting for Cane...';
      });
      
      _serverSocket!.listen(
        (Socket client) {
          _connectedClient = client;
          final clientAddress = client.remoteAddress.address;
          print('>> CLIENT CONNECTED: $clientAddress');
          
          setState(() {
            _connectionStatus = 'Connected: $clientAddress';
          });
          
          // Announce connection via voice
          _voiceService.speak('স্মার্ট ক্যান সংযুক্ত। Smart Cane connected.');
          
          client.listen(
            (List<int> data) {
              final message = String.fromCharCodes(data).trim();
              print('>> RECEIVED: $message');
              _handleIncomingMessage(message);
            },
            onError: (error) {
              print('>> CLIENT ERROR: $error');
              setState(() {
                _connectionStatus = 'Connection Error';
                _connectedClient = null;
              });
            },
            onDone: () {
              print('>> CLIENT DISCONNECTED');
              setState(() {
                _connectionStatus = 'Cane Disconnected';
                _connectedClient = null;
              });
            },
            cancelOnError: false,
          );
        },
        onError: (error) {
          print('>> SERVER ERROR: $error');
          setState(() {
            _connectionStatus = 'Server Error';
          });
        },
      );
    } catch (e) {
      print('>> SOCKET BIND ERROR: $e');
      setState(() {
        _connectionStatus = 'Failed to start server: $e';
      });
    }
  }
  
  /// Stops the TCP server and closes connections
  void _stopTcpServer() {
    _connectedClient?.close();
    _serverSocket?.close();
    _connectedClient = null;
    _serverSocket = null;
  }
  
  /// Gets the device's WiFi IP address
  Future<void> _getDeviceIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      
      for (var interface in interfaces) {
        // Look for WiFi interface
        if (interface.name.toLowerCase().contains('wlan') ||
            interface.name.toLowerCase().contains('wifi') ||
            interface.name.toLowerCase().contains('en0') ||
            interface.name.toLowerCase().contains('eth')) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              setState(() {
                _deviceIpAddress = addr.address;
              });
              return;
            }
          }
        }
      }
      
      // Fallback: use any IPv4 address found
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            setState(() {
              _deviceIpAddress = addr.address;
            });
            return;
          }
        }
      }
      
      setState(() {
        _deviceIpAddress = 'Not found';
      });
    } catch (e) {
      print('>> Failed to get IP: $e');
      setState(() {
        _deviceIpAddress = 'Error: $e';
      });
    }
  }
  
  /// Handles incoming messages from the Raspberry Pi
  void _handleIncomingMessage(String message) {
    setState(() {
      _latestAlert = message;
    });
    
    // Speak the alert (logged to console in stub mode)
    _voiceService.speak(message);
  }
  
  /// Shows a critical alert dialog for emergency warnings
  void _showCriticalAlertDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
              SizedBox(width: AppConstants.spacingM),
              const Expanded(
                child: Text(
                  '⚠️ CRITICAL ALERT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            padding: EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.error,
                  padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
                ),
                child: const Text(
                  'DISMISS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _initializeServices() async {
    await _voiceService.initialize();
    setState(() {
      _isInitialized = true;
    });
    
    // Welcome message
    await Future.delayed(const Duration(milliseconds: 500));
    await _voiceService.speak(
      'স্মার্ট ক্যান অ্যাপে স্বাগতম। বলুন কোথায় যেতে চান। Welcome to Smart Cane. Say where you want to go.',
    );
  }
  
  void _setupNavigationCallback() {
    _voiceService.onNavigationAction = (action) {
      switch (action) {
        case VoiceAction.navigateHome:
          // Already on home
          break;
        case VoiceAction.navigateLocation:
          Navigator.pushNamed(context, AppRoutes.location);
          break;
        case VoiceAction.navigateSettings:
          Navigator.pushNamed(context, AppRoutes.settings);
          break;
        case VoiceAction.navigateHelp:
          Navigator.pushNamed(context, AppRoutes.help);
          break;
        case VoiceAction.speakBattery:
          _voiceService.speak('ব্যাটারি ৮৫ শতাংশ। Battery is 85 percent.');
          break;
        case VoiceAction.speakTime:
          final now = TimeOfDay.now();
          _voiceService.speak('সময় ${now.hour}:${now.minute}। Time is ${now.format(context)}.');
          break;
        case VoiceAction.none:
          break;
      }
    };
  }
  
  void _toggleVoiceListening() async {
    if (_voiceService.isListening) {
      await _voiceService.stopListening();
    } else {
      await _voiceService.startListening();
    }
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Semantics(
          header: true,
          label: '${AppConstants.appName}। ${AppConstants.appNameEn}',
          child: Column(
            children: [
              Text(AppConstants.appName),
              Text(
                AppConstants.appNameEn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _voiceService,
          builder: (context, child) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(AppConstants.spacingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Voice Indicator Header
                  Card(
                    elevation: 4,
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.spacingXl),
                      child: Column(
                        children: [
                          VoiceIndicator(
                            isListening: _voiceService.isListening,
                            size: 120,
                          ),
                          SizedBox(height: AppConstants.spacingL),
                          
                          // Status text
                          Text(
                            _voiceService.isProcessing
                                ? 'চিন্তা করছি...'
                                : _voiceService.isListening
                                    ? 'শুনছি...'
                                    : 'ভয়েস কমান্ড',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _voiceService.isListening 
                                  ? AppColors.accent 
                                  : _voiceService.isProcessing
                                      ? AppColors.info
                                      : AppColors.primary,
                            ),
                          ),
                          SizedBox(height: AppConstants.spacingXs),
                          Text(
                            _voiceService.isProcessing
                                ? 'Processing...'
                                : _voiceService.isListening
                                    ? 'Listening...'
                                    : 'Voice Command',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          
                          // Transcript display
                          if (_voiceService.currentTranscript.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                              ),
                              child: Text(
                                '"${_voiceService.currentTranscript}"',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          
                          // Last response
                          if (_voiceService.lastResponse.isNotEmpty && 
                              !_voiceService.isListening && 
                              !_voiceService.isProcessing) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                                border: Border.all(color: AppColors.success.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: AppColors.success),
                                  SizedBox(width: AppConstants.spacingS),
                                  Expanded(
                                    child: Text(
                                      _voiceService.lastResponse,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          SizedBox(height: AppConstants.spacingL),
                          
                          // Listen button
                          FilledButton.icon(
                            onPressed: _isInitialized ? _toggleVoiceListening : null,
                            icon: Icon(
                              _voiceService.isListening ? Icons.mic_off : Icons.mic,
                            ),
                            label: Text(
                              _voiceService.isListening 
                                  ? 'থামান (Stop)' 
                                  : 'শুরু করুন (Start)',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _voiceService.isListening 
                                  ? AppColors.error 
                                  : AppColors.accent,
                              padding: EdgeInsets.symmetric(
                                horizontal: AppConstants.spacingXl,
                                vertical: AppConstants.spacingL,
                              ),
                            ),
                          ),
                          
                          // Error display
                          if (_voiceService.error.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Text(
                              _voiceService.error,
                              style: TextStyle(color: AppColors.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: AppConstants.spacingL),
                  
                  // TCP Connection Status Card
                  Card(
                    elevation: 4,
                    color: _connectedClient != null 
                        ? AppColors.success.withOpacity(0.1)
                        : Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      side: BorderSide(
                        color: _connectedClient != null 
                            ? AppColors.success 
                            : AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.spacingL),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Icon(
                                _connectedClient != null 
                                    ? Icons.wifi 
                                    : Icons.wifi_off,
                                color: _connectedClient != null 
                                    ? AppColors.success 
                                    : AppColors.warning,
                                size: 28,
                              ),
                              SizedBox(width: AppConstants.spacingM),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ক্যান কানেকশন / Cane Connection',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: AppConstants.spacingXs),
                                    Text(
                                      _connectionStatus,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: _connectedClient != null 
                                            ? AppColors.success 
                                            : AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Connection indicator dot
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _connectedClient != null 
                                      ? AppColors.success 
                                      : AppColors.warning,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_connectedClient != null 
                                          ? AppColors.success 
                                          : AppColors.warning).withOpacity(0.5),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          // Device IP Address Display (for Raspberry Pi configuration)
                          SizedBox(height: AppConstants.spacingM),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(AppConstants.spacingS),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(AppConstants.radiusS),
                              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lan, color: AppColors.primary, size: 18),
                                SizedBox(width: AppConstants.spacingS),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Connect Pi to / পাই কানেক্ট করুন:',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      Text(
                                        '$_deviceIpAddress:4444',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Latest Alert Display
                          if (_latestAlert.isNotEmpty) ...[
                            SizedBox(height: AppConstants.spacingM),
                            Divider(color: AppColors.primary.withOpacity(0.2)),
                            SizedBox(height: AppConstants.spacingM),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(AppConstants.spacingM),
                              decoration: BoxDecoration(
                                color: _latestAlert.toUpperCase().contains('CRITICAL')
                                    ? AppColors.error.withOpacity(0.15)
                                    : AppColors.info.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppConstants.radiusS),
                                border: Border.all(
                                  color: _latestAlert.toUpperCase().contains('CRITICAL')
                                      ? AppColors.error.withOpacity(0.5)
                                      : AppColors.info.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _latestAlert.toUpperCase().contains('CRITICAL')
                                            ? Icons.warning_amber_rounded
                                            : Icons.notifications_active,
                                        color: _latestAlert.toUpperCase().contains('CRITICAL')
                                            ? AppColors.error
                                            : AppColors.info,
                                        size: 20,
                                      ),
                                      SizedBox(width: AppConstants.spacingS),
                                      Text(
                                        'সর্বশেষ সতর্কতা / Latest Alert',
                                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _latestAlert.toUpperCase().contains('CRITICAL')
                                              ? AppColors.error
                                              : AppColors.info,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: AppConstants.spacingS),
                                  Text(
                                    _latestAlert,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: AppConstants.spacingXl),
                  
                  // Text input for testing (helpful for demo)
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppConstants.spacingM),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'টেস্ট কমান্ড / Test Command',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          SizedBox(height: AppConstants.spacingS),
                          TextField(
                            decoration: InputDecoration(
                              hintText: 'Type a command...',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () {
                                  // Get text from controller and send
                                },
                              ),
                            ),
                            onSubmitted: (text) {
                              if (text.isNotEmpty) {
                                _voiceService.sendTextCommand(text);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(height: AppConstants.spacingXl),
                  
                  // Navigation Header
                  Semantics(
                    header: true,
                    label: 'নেভিগেশন অপশন। Navigation options.',
                    child: Text(
                      'কোথায় যেতে চান? / Where to go?',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  
                  SizedBox(height: AppConstants.spacingL),
                  
                  // Main Navigation Grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppConstants.spacingL,
                    crossAxisSpacing: AppConstants.spacingL,
                    childAspectRatio: 0.9,
                    children: [
                      AccessibleActionButton(
                        icon: Icons.location_on,
                        label: 'আমি কোথায়?',
                        labelEn: 'Where am I?',
                        semanticHint: 'আপনার বর্তমান অবস্থান দেখুন।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.location),
                        color: AppColors.info,
                      ),
                      AccessibleActionButton(
                        icon: Icons.settings,
                        label: 'সেটিংস',
                        labelEn: 'Settings',
                        semanticHint: 'সেটিংস খুলুন।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
                        color: AppColors.primary,
                      ),
                      AccessibleActionButton(
                        icon: Icons.help_outline,
                        label: 'সাহায্য',
                        labelEn: 'Help',
                        semanticHint: 'সাহায্য এবং টিউটোরিয়াল।',
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.help),
                        color: AppColors.success,
                      ),
                      AccessibleActionButton(
                        icon: Icons.battery_charging_full,
                        label: 'ব্যাটারি',
                        labelEn: 'Battery',
                        semanticHint: 'ব্যাটারি স্ট্যাটাস।',
                        onPressed: () {
                          _voiceService.speak('ব্যাটারি ৮৫ শতাংশ। Battery is 85 percent.');
                        },
                        color: AppColors.warning,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
