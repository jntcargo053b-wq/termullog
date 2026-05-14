// lib/services/location_weather_service.dart

// ... existing imports ...

class LocationWeatherService {
  
  // ... existing methods ...

  static Future<Uint8List?> fetchMapWithRetry(
    double lat,
    double lon, {
    int maxRetries = 2,
  }) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        attempt++;
        debugPrint('🗺️ Map fetch attempt $attempt/$maxRetries');
        
        final client = http.Client();
        
        // PERBAIKAN: Gunakan marker yang valid untuk OSM
        // Valid markers: ol-marker, ol-marker-blue, ol-marker-green, 
        // ol-marker-red, ol-marker-gold, ol-marker-black
        final url = Uri.parse(
          'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lon'
          '&zoom=16'
          '&size=400x300'
          '&maptype=mapnik'
          '&markers=$lat,$lon,ol-marker'  // PERBAIKAN: ol-marker (merah)
        );
        
        debugPrint('🗺️ Map URL: $url');
        
        final response = await client.get(
          url,
          headers: {
            'User-Agent': 'TermulLog/1.0',
            'Accept': 'image/png',
          },
        ).timeout(const Duration(seconds: 15));
        
        client.close();
        
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          
          // PERBAIKAN: Validasi bahwa response benar-benar gambar PNG
          if (bytes.length > 4 && 
              bytes[0] == 0x89 && 
              bytes[1] == 0x50 && 
              bytes[2] == 0x4E && 
              bytes[3] == 0x47) {
            // Valid PNG header
            debugPrint('✅ Valid PNG map received: ${bytes.length} bytes');
            return bytes;
          } else {
            // Mungkin error text dari server
            final text = String.fromCharCodes(bytes.take(200));
            debugPrint('❌ Response bukan gambar PNG: $text');
            return null;
          }
        } else {
          debugPrint('❌ Map API returned HTTP ${response.statusCode}');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: attempt * 2));
          }
        }
      } catch (e) {
        debugPrint('❌ Map fetch error (attempt $attempt): $e');
        if (attempt >= maxRetries) {
          return null;
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    
    return null;
  }
  
  // ... existing methods ...
}
