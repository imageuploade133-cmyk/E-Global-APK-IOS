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
    // Handling photo / storage permission based on SDKs
    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    final photosStatus = await Permission.photos.request();
    return photosStatus.isGranted;
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
