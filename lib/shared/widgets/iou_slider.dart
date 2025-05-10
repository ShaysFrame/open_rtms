import 'package:flutter/material.dart';

/// A reusable slider widget for adjusting the IoU threshold
class IoUSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;

  const IoUSlider({
    Key? key,
    required this.value,
    required this.onChanged,
    this.min = 0.1,
    this.max = 0.9,
    this.divisions = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Text('IoU threshold: '),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(1),
              onChanged: onChanged,
            ),
          ),
          Text('${(value * 100).toInt()}%'),
        ],
      ),
    );
  }
}
