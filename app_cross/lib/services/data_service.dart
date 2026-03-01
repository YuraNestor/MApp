import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PointData {
  final String timestamp;
  final double lat;
  final double lng;
  final double roughness;
  final double speed;
  final double heading;

  PointData({
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.roughness,
    required this.speed,
    required this.heading,
  });

  String toCsvRow() {
    return '$timestamp,$lat,$lng,$roughness,$speed,$heading\n';
  }
}

class DataService {
  Future<void> exportCsv(List<PointData> points) async {
    if (points.isEmpty) {
      throw Exception('No data to export.');
    }

    // Generate CSV string
    StringBuffer csvData = StringBuffer();
    csvData.write('timestamp,lat,lng,roughness,speed,heading\n');
    for (var point in points) {
      csvData.write(point.toCsvRow());
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final defaultFileName = 'road_roughness_log_$timestamp.csv';

      // Ask user where to save the file natively
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CSV Data',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (outputFile != null) {
        // User picked a path, write directly to it
        final file = File(outputFile);
        await file.writeAsString(csvData.toString());
      } else {
         // Fallback if saveFile returns null or user cancels, or platform doesn't support it fully
         // Get the temporary directory
         final directory = await getTemporaryDirectory();
         final path = '${directory.path}/$defaultFileName';
         final file = File(path);
         await file.writeAsString(csvData.toString());
         
         // Share the file
         await Share.shareXFiles([XFile(path)], text: 'Exported Road Roughness Data');
      }
    } catch (e) {
      print("Error exporting CSV: $e");
      rethrow;
    }
  }
}
