@IsTest
private class WeatherEmailBuilderTest {

    private static GeoNamesWeatherService.WeatherData sample() {
        GeoNamesWeatherService.WeatherData w = new GeoNamesWeatherService.WeatherData();
        w.locationName = 'Marseille';
        w.condition = 'Light rain';
        w.temperature = 18;
        w.humidity = 72;
        w.windSpeedKmh = 18.5;
        w.stationName = 'Marseille Provence';
        w.observationTime = '2026-09-20 10:00:00';
        return w;
    }

    @IsTest
    static void subjectIncludesLocation() {
        Assert.areEqual('Weather report – Marseille', WeatherEmailBuilder.buildSubject(sample()));
    }

    @IsTest
    static void htmlIncludesAllMetricsAndEscapesLocation() {
        GeoNamesWeatherService.WeatherData w = sample();
        w.locationName = 'R&D City'; 
        String html = WeatherEmailBuilder.buildHtml(w);
        Assert.isTrue(html.contains('R&amp;D City'));
        Assert.isTrue(html.contains('18 °C'));
        Assert.isTrue(html.contains('72 %'));
        Assert.isTrue(html.contains('18.5 km/h'));
        Assert.isTrue(html.contains('Marseille Provence'));
    }

    @IsTest
    static void plainTextHandlesMissingMetrics() {
        GeoNamesWeatherService.WeatherData w = sample();
        w.temperature = null;
        w.humidity = null;
        w.windSpeedKmh = null;
        String plain = WeatherEmailBuilder.buildPlain(w);
        Assert.isTrue(plain.contains('Temperature: n/a'));
        Assert.isTrue(plain.contains('Humidity: n/a'));
        Assert.isTrue(plain.contains('Wind speed: n/a'));
    }
}
