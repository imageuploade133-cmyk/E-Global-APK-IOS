import 'package:permission_handler/permission_handler.dart';

abstract class PermissionService {
  Future<bool> requestCameraPermission();
  Future<bool> requestMicrophonePermission();
  Future<bool> requestLocationPermission();
  Future<bool> requestStoragePermission();
  Future<bool> requestNotificationPermission();
  Future<bool> hasPermission(Permission permission);
}

class PermissionServiceImpl implements PermissionService {
  @override
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  @override
  Future<bool> requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  @override
  Future<bool> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  @override
  Future<bool> requestStoragePermission() async {
    // Application uses app-private documents storage for downloads; broad external storage permissions are unnecessary.
    return true;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  @override
  Future<bool> hasPermission(Permission permission) async {
    return await permission.isGranted;
  }
}
