import 'package:flutter/material.dart';
import '../handlers/aprs_handler.dart';

/// Dialog for displaying APRS weather station data.
class AprsWeatherDialog extends StatelessWidget {
  final AprsEntry entry;

  const AprsWeatherDialog({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final comment = entry.packet.comment;

    // Parse weather fields from APRS comment (APRS weather format)
    final fields = <String, String>{};
    fields['Station'] = entry.from;
    fields['Time'] = _formatTime(entry.time);

    // Weather data is encoded in the comment field using APRS weather format
    // c=wind direction, s=wind speed, g=gust, t=temp, r=rain 1h, p=rain 24h,
    // P=rain midnight, h=humidity, b=barometric pressure
    if (comment.isNotEmpty) {
      final wx = _parseWeatherComment(comment);
      if (wx['wind_dir'] != null) fields['Wind Direction'] = '${wx['wind_dir']}°';
      if (wx['wind_speed'] != null) fields['Wind Speed'] = '${wx['wind_speed']} mph';
      if (wx['wind_gust'] != null) fields['Wind Gust'] = '${wx['wind_gust']} mph';
      if (wx['temperature'] != null) fields['Temperature'] = '${wx['temperature']}°F';
      if (wx['rain_1h'] != null) fields['Rain (1h)'] = '${wx['rain_1h']} in';
      if (wx['rain_24h'] != null) fields['Rain (24h)'] = '${wx['rain_24h']} in';
      if (wx['humidity'] != null) fields['Humidity'] = '${wx['humidity']}%';
      if (wx['pressure'] != null) fields['Pressure'] = '${wx['pressure']} mbar';
      if (wx.isEmpty || wx.values.every((v) => v == null)) {
        fields['Raw Comment'] = comment;
      }
    }

    return Dialog(
      backgroundColor: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('WEATHER REPORT',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.onSurfaceVariant)),
              const SizedBox(height: 16),
              ...fields.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(
                        width: 120,
                        child: Text(e.key,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.onSurfaceVariant)),
                      ),
                      Expanded(
                          child: Text(e.value,
                              style: TextStyle(
                                  fontSize: 11, color: colors.onSurface))),
                    ]),
                  )),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: colors.onSurfaceVariant))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Parses APRS positionless weather data from comment.
  /// Format: cDDD sSSSgGGGtTTTrRRRpPPPPPPhHHbBBBBB
  Map<String, String?> _parseWeatherComment(String comment) {
    final result = <String, String?>{};
    final s = comment;

    // Wind direction: c followed by 3 digits
    final cMatch = RegExp(r'c(\d{3})').firstMatch(s);
    if (cMatch != null) result['wind_dir'] = cMatch.group(1);

    // Wind speed: s followed by 3 digits
    final sMatch = RegExp(r's(\d{3})').firstMatch(s);
    if (sMatch != null) result['wind_speed'] = sMatch.group(1);

    // Wind gust: g followed by 3 digits
    final gMatch = RegExp(r'g(\d{3})').firstMatch(s);
    if (gMatch != null) result['wind_gust'] = gMatch.group(1);

    // Temperature: t followed by 3 digits (can be negative with leading -)
    final tMatch = RegExp(r't(-?\d{2,3})').firstMatch(s);
    if (tMatch != null) result['temperature'] = tMatch.group(1);

    // Rain 1 hour: r followed by 3 digits (hundredths of inch)
    final rMatch = RegExp(r'r(\d{3})').firstMatch(s);
    if (rMatch != null) {
      final val = int.tryParse(rMatch.group(1)!);
      if (val != null) result['rain_1h'] = (val / 100).toStringAsFixed(2);
    }

    // Rain 24 hours: p followed by 3 digits
    final pMatch = RegExp(r'p(\d{3})').firstMatch(s);
    if (pMatch != null) {
      final val = int.tryParse(pMatch.group(1)!);
      if (val != null) result['rain_24h'] = (val / 100).toStringAsFixed(2);
    }

    // Humidity: h followed by 2 digits (00=100%)
    final hMatch = RegExp(r'h(\d{2})').firstMatch(s);
    if (hMatch != null) {
      final val = hMatch.group(1)!;
      result['humidity'] = val == '00' ? '100' : val;
    }

    // Barometric pressure: b followed by 5 digits (tenths of mbar)
    final bMatch = RegExp(r'b(\d{5})').firstMatch(s);
    if (bMatch != null) {
      final val = int.tryParse(bMatch.group(1)!);
      if (val != null) result['pressure'] = (val / 10).toStringAsFixed(1);
    }

    return result;
  }

  String _formatTime(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
