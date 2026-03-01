import 'package:flutter/material.dart';

class SettingsDialog extends StatefulWidget {
  final double sensitivityMultiplier;
  final double speedInfluenceMultiplier;
  final String currentStyle;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final Function(double) onSensitivityChanged;
  final Function(double) onSpeedInfluenceChanged;
  final Function(String) onStyleChanged;

  const SettingsDialog({
    super.key,
    required this.sensitivityMultiplier,
    required this.speedInfluenceMultiplier,
    required this.currentStyle,
    required this.onExport,
    required this.onImport,
    required this.onSensitivityChanged,
    required this.onSpeedInfluenceChanged,
    required this.onStyleChanged,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late double _sensitivity;
  late double _speedInfluence;
  late String _currentStyle;

  @override
  void initState() {
    super.initState();
    _sensitivity = widget.sensitivityMultiplier;
    _speedInfluence = widget.speedInfluenceMultiplier;
    _currentStyle = widget.currentStyle;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                )
              ],
            ),
            const Divider(color: Colors.grey),
            const SizedBox(height: 10),
            
            // Map Style
            const Text('Map Style', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _styleButton('Dark', 'mapbox://styles/mapbox/dark-v11'),
                  const SizedBox(width: 8),
                  _styleButton('Streets', 'mapbox://styles/mapbox/streets-v12'),
                  const SizedBox(width: 8),
                  _styleButton('Satellite', 'mapbox://styles/mapbox/satellite-streets-v12'),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Sensitivity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bump Sensitivity', style: TextStyle(color: Colors.white)),
                Text('${_sensitivity.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            Slider(
              value: _sensitivity,
              min: 0.1,
              max: 3.0,
              divisions: 29,
              activeColor: Colors.blueAccent,
              onChanged: (val) {
                setState(() => _sensitivity = val);
                widget.onSensitivityChanged(val);
              },
            ),
            
            // Speed Influence
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Speed Influence', style: TextStyle(color: Colors.white)),
                Text('${_speedInfluence.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            Slider(
              value: _speedInfluence,
              min: 0.0,
              max: 5.0,
              divisions: 50,
              activeColor: Colors.purpleAccent,
              onChanged: (val) {
                setState(() => _speedInfluence = val);
                widget.onSpeedInfluenceChanged(val);
              },
            ),
            
            const SizedBox(height: 20),
            
            // Actions
            const Text('Data Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onExport();
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Export Csv'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.2),
                      foregroundColor: Colors.blueAccent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onImport();
                    },
                    icon: const Icon(Icons.file_download),
                    label: const Text('Import Csv'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.withOpacity(0.2),
                      foregroundColor: Colors.greenAccent,
                    ),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _styleButton(String label, String url) {
    bool isSelected = _currentStyle == url;
    return GestureDetector(
      onTap: () {
        setState(() => _currentStyle = url);
        widget.onStyleChanged(url);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.white : Colors.grey[400]),
        ),
      ),
    );
  }
}
