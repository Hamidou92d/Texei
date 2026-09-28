/**
 * Thin wrapper around the GeoNames JSON web services:
 *  - searchJSON                 : city name  -> lat/lng
 *  - findNearByWeatherJSON      : lat/lng    -> latest weather observation (nearest ICAO station)
 *  - findNearbyPlaceNameJSON    : lat/lng    -> place name (best effort, for display)
 */
public with sharing class GeoNamesWeatherService {

    public class WeatherException extends Exception {}

    private static final String BASE_URL = 'callout:GeoNames';
    private static final Decimal KMH_PER_KNOT = 1.852;

    public class GeoLocation {
        public String name;
        public String country;
        public Decimal lat;
        public Decimal lng;
    }

    public class WeatherData {
        @AuraEnabled public String locationName;
        @AuraEnabled public String country;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Decimal temperature;      // °C
        @AuraEnabled public Integer humidity;         // %
        @AuraEnabled public Decimal windSpeedKnots;   // GeoNames returns knots
        @AuraEnabled public Decimal windSpeedKmh;
        @AuraEnabled public String condition;         
        @AuraEnabled public String iconKey;           // sunny | partly | cloudy | rain | snow | storm | fog | unknown
        @AuraEnabled public String stationName;
        @AuraEnabled public String observationTime;
    }

    // ------------------------------------------------------------------ public API

    public static GeoLocation geocode(String cityName) {
        Map<String, Object> body = call('/searchJSON', new Map<String, String>{
            'q' => cityName, 'maxRows' => '1', 'style' => 'SHORT'
        });
        List<Object> results = (List<Object>) body.get('geonames');
        if (results == null || results.isEmpty()) {
            throw new WeatherException('No location found for "' + cityName + '".');
        }
        Map<String, Object> r = (Map<String, Object>) results[0];
        GeoLocation loc = new GeoLocation();
        loc.name = (String) r.get('name');
        loc.country = (String) r.get('countryName');
        loc.lat = toDecimal(r.get('lat'));
        loc.lng = toDecimal(r.get('lng'));
        return loc;
    }

    public static WeatherData getWeather(Decimal lat, Decimal lng, GeoLocation knownPlace) {
        validate(lat, lng);
        Map<String, Object> body = call('/findNearByWeatherJSON', new Map<String, String>{
            'lat' => String.valueOf(lat), 'lng' => String.valueOf(lng)
        });
        Map<String, Object> obs = (Map<String, Object>) body.get('weatherObservation');
        if (obs == null) {
            throw new WeatherException('No weather station found near this location.');
        }

        WeatherData w = new WeatherData();
        w.latitude = lat;
        w.longitude = lng;
        w.temperature = toDecimal(obs.get('temperature'));
        Decimal h = toDecimal(obs.get('humidity'));
        w.humidity = h == null ? null : h.intValue();
        w.windSpeedKnots = toDecimal(obs.get('windSpeed'));
        w.windSpeedKmh = w.windSpeedKnots == null ? null : (w.windSpeedKnots * KMH_PER_KNOT).setScale(1);
        w.stationName = (String) obs.get('stationName');
        w.observationTime = (String) obs.get('datetime');

        String cond = (String) obs.get('weatherCondition');
        String clouds = (String) obs.get('clouds');
        String cloudsCode = (String) obs.get('cloudsCode');
        w.iconKey = resolveIcon(cond, clouds, cloudsCode);
        w.condition = describe(cond, clouds);

        if (knownPlace != null) {
            w.locationName = knownPlace.name;
            w.country = knownPlace.country;
        } else {
            reverseName(w);
        }
        if (String.isBlank(w.locationName)) {
            w.locationName = lat.setScale(3) + ', ' + lng.setScale(3);
        }
        return w;
    }

    @TestVisible
    private static String resolveIcon(String cond, String clouds, String cloudsCode) {
        String c = String.isBlank(cond) ? '' : cond.toLowerCase();
        if (c.contains('thunder') || c.contains('storm')) return 'storm';
        if (c.contains('snow') || c.contains('sleet') || c.contains('hail') || c.contains('ice')) return 'snow';
        if (c.contains('rain') || c.contains('drizzle') || c.contains('shower')) return 'rain';
        if (c.contains('fog') || c.contains('mist') || c.contains('haze')) return 'fog';

        String code = String.isBlank(cloudsCode) ? '' : cloudsCode.toUpperCase();
        if (new Set<String>{ 'CAVOK', 'CLR', 'SKC', 'NSC', 'NCD' }.contains(code)) return 'sunny';
        if (code == 'FEW' || code == 'SCT') return 'partly';
        if (code == 'BKN' || code == 'OVC' || code == 'VV') return 'cloudy';

        String t = String.isBlank(clouds) ? '' : clouds.toLowerCase();
        if (t.contains('clear')) return 'sunny';
        if (t.contains('few') || t.contains('scattered')) return 'partly';
        if (t.contains('broken') || t.contains('overcast') || t.contains('cloud')) return 'cloudy';
        return 'unknown';
    }

    // ------------------------------------------------------------------ internals

    private static String describe(String cond, String clouds) {
        Boolean hasCond = !String.isBlank(cond) && cond.toLowerCase() != 'n/a';
        Boolean hasClouds = !String.isBlank(clouds) && clouds.toLowerCase() != 'n/a';
        if (hasCond && hasClouds) return capitalize(cond) + ' – ' + clouds;
        if (hasCond) return capitalize(cond);
        if (hasClouds) return capitalize(clouds);
        return 'Unknown';
    }

    private static String username() {
        Weather_Setting__mdt s = Weather_Setting__mdt.getInstance('Default'); // Default is the label of the Custom Metadata Type Record Name
        if (s == null || String.isBlank(s.Geonames_Username__c)) {
            throw new WeatherException('GeoNames username is not configured (Custom Metadata Type "Weather Setting" > Default).');
        }
        return s.Geonames_Username__c;
    }

    private static String capitalize(String s) {
        return s.substring(0, 1).toUpperCase() + s.substring(1);
    }

    private static void reverseName(WeatherData w) {
        try {
            Map<String, Object> body = call('/findNearbyPlaceNameJSON', new Map<String, String>{
                'lat' => String.valueOf(w.latitude), 'lng' => String.valueOf(w.longitude),
                'maxRows' => '1', 'style' => 'SHORT'
            });
            List<Object> results = (List<Object>) body.get('geonames');
            if (results != null && !results.isEmpty()) {
                Map<String, Object> r = (Map<String, Object>) results[0];
                w.locationName = (String) r.get('name');
                w.country = (String) r.get('countryName');
            }
        } catch (Exception e) {
            // Best effort only – coordinates will be displayed instead
            System.debug(LoggingLevel.WARN, 'Reverse geocoding failed: ' + e.getMessage());
        }
    }

    private static void validate(Decimal lat, Decimal lng) {
        if (lat == null || lng == null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            throw new WeatherException('Invalid coordinates. Latitude must be within ±90 and longitude within ±180.');
        }
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) return null;
        String s = String.valueOf(o).trim();
        if (String.isBlank(s) || s.toLowerCase() == 'n/a') return null;
        try { return Decimal.valueOf(s); } catch (Exception e) { return null; }
    }

    private static Map<String, Object> call(String path, Map<String, String> params) {
        params.put('username', username());
        List<String> pairs = new List<String>();
        for (String k : params.keySet()) {
            pairs.add(k + '=' + EncodingUtil.urlEncode(params.get(k), 'UTF-8'));
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + path + '?' + String.join(pairs, '&'));
        req.setMethod('GET');
        req.setTimeout(12000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new WeatherException('GeoNames returned HTTP ' + res.getStatusCode() + '.');
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (body.containsKey('status')) {
            Map<String, Object> st = (Map<String, Object>) body.get('status');
            throw new WeatherException('GeoNames error: ' + st.get('message'));
        }
        return body;
    }
}
