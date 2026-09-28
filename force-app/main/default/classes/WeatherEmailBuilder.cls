/**
 * Template rendering: WeatherData in, e-mail subject/HTML/plain text out.
 * No SOQL, no DML, no callouts.
 */
public inherited sharing class WeatherEmailBuilder {

    public static String buildSubject(GeoNamesWeatherService.WeatherData w) {
        return 'Weather report – ' + w.locationName;
    }

    public static String buildHtml(GeoNamesWeatherService.WeatherData w) {
        return '<div style="font-family:Arial,sans-serif;color:#032d60">'
            + '<h2 style="margin:0 0 8px">Weather report – ' + esc(w.locationName) + '</h2>'
            + '<p style="margin:0 0 12px">' + esc(w.condition) + '</p>'
            + '<table cellpadding="6" style="border-collapse:collapse">'
            + row('Temperature', w.temperature == null ? 'n/a' : w.temperature + ' °C')
            + row('Humidity', w.humidity == null ? 'n/a' : w.humidity + ' %')
            + row('Wind speed', w.windSpeedKmh == null ? 'n/a' : w.windSpeedKmh + ' km/h')
            + '</table>'
            + '<p style="color:#5c5c5c;font-size:12px">Station: ' + esc(w.stationName)
            + ' – observed ' + esc(w.observationTime) + ' (source: GeoNames)</p></div>';
    }

    public static String buildPlain(GeoNamesWeatherService.WeatherData w) {
        return 'Weather report – ' + w.locationName + '\n'
            + w.condition + '\n'
            + 'Temperature: ' + (w.temperature == null ? 'n/a' : w.temperature + ' °C') + '\n'
            + 'Humidity: ' + (w.humidity == null ? 'n/a' : w.humidity + ' %') + '\n'
            + 'Wind speed: ' + (w.windSpeedKmh == null ? 'n/a' : w.windSpeedKmh + ' km/h') + '\n'
            + 'Station: ' + w.stationName + ' – observed ' + w.observationTime;
    }

    private static String row(String label, String value) {
        return '<tr><td style="border-bottom:1px solid #e5e5e5"><b>' + label + '</b></td>'
            + '<td style="border-bottom:1px solid #e5e5e5">' + value + '</td></tr>';
    }

    private static String esc(String s) {
        return s == null ? '' : s.escapeHtml4();
    }
}
