import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PointData {
  final double lat;
  final double lng;
  final double roughness;
  final String time;

  PointData({required this.lat, required this.lng, required this.roughness, required this.time});

  String toCsvRow() {
    return '$lat,$lng,$roughness,$time\n';
  }
}

class DataService {
  Future<void> exportCsv(List<PointData> points) async {
    if (points.isEmpty) {
      throw Exception('No data to export.');
    }

    // Generate CSV string
    StringBuffer csvData = StringBuffer();
    csvData.write('Latitude,Longitude,Roughness,Time\n');
    for (var point in points) {
      csvData.write(point.toCsvRow());
    }

    try {
      // Get the temporary directory
      final directory = await getTemporaryDirectory();
      
      // Make a unique file name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${directory.path}/road_roughness_log_$timestamp.csv';
      
      // Write to file
      final file = File(path);
      await file.writeAsString(csvData.toString());
      
      // Share the file
      await Share.shareXFiles([XFile(path)], text: 'Exported Road Roughness Data');
      
    } catch (e) {
      print("Error exporting CSV: $e");
      rethrow;
    }
  }
}
