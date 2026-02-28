import 'package:flutter/material.dart';

class NavigationOverlay extends StatelessWidget {
  final bool isRecording;
  final double currentRoughness;
  final double? currentSpeedKmH;
  final VoidCallback onRecordToggle;

  const NavigationOverlay({
    super.key,
    required this.isRecording,
    required this.currentRoughness,
    this.currentSpeedKmH,
    required this.onRecordToggle,
  });

  Color _getRoughnessColor(double roughness) {
    if (roughness == 1) return Colors.green;
    if (roughness == 2) return Colors.yellow;
    if (roughness == 3) return Colors.orange;
    if (roughness == 4) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.only(bottom: 30, top: 20, left: 20, right: 20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Status Info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isRecording ? Colors.red : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isRecording ? 'Recording Active' : 'Ready to Record',
                      style: TextStyle(
                        color: isRecording ? Colors.white : Colors.grey[400],
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.speed, color: Colors.grey, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      '${currentSpeedKmH?.toStringAsFixed(1) ?? "0.0"} km/h',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Roughness: ',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getRoughnessColor(currentRoughness).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _getRoughnessColor(currentRoughness)),
                      ),
                      child: Text(
                        currentRoughness.toInt().toString(),
                        style: TextStyle(
                          color: _getRoughnessColor(currentRoughness),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
            
            // Record Action
            GestureDetector(
              onTap: onRecordToggle,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: isRecording ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isRecording ? Colors.red : Colors.green,
                    width: 2,
                  ),
                ),
                child: Icon(
                  isRecording ? Icons.stop : Icons.play_arrow,
                  color: isRecording ? Colors.red : Colors.green,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
