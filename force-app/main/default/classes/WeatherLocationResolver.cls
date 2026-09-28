/**
 * Resolves "where" (a free-text query, an Account, or the current User) into a
 * WeatherData record. Owns the only SOQL related to *finding a location* 
 */
public with sharing class WeatherLocationResolver {

    private static final Pattern COORDS = Pattern.compile('^(-?\\d+(\\.\\d+)?)\\s*[,;\\s]\\s*(-?\\d+(\\.\\d+)?)$');

    /** Free text: either "City" or "lat,lng". */
    public static GeoNamesWeatherService.WeatherData resolveByQuery(String query) {
        if (String.isBlank(query)) {
            throw new GeoNamesWeatherService.WeatherException('You should enter a city name or coordinates (lat, lng).');
        }
        Matcher m = COORDS.matcher(query.trim());
        if (m.matches()) {
            return GeoNamesWeatherService.getWeather(Decimal.valueOf(m.group(1)), Decimal.valueOf(m.group(3)), null);
        }
        GeoNamesWeatherService.GeoLocation loc = GeoNamesWeatherService.geocode(query.trim());
        return GeoNamesWeatherService.getWeather(loc.lat, loc.lng, loc);
    }

    /** Use first billing coordinates, if not available then shipping coordinates, then the billing/shipping city. */
    public static GeoNamesWeatherService.WeatherData resolveForAccount(Id accountId) {
        Account a = [
            SELECT Name, BillingLatitude, BillingLongitude, BillingCity, BillingCountry,
                   ShippingLatitude, ShippingLongitude, ShippingCity, ShippingCountry
            FROM Account WHERE Id = :accountId WITH USER_MODE LIMIT 1
        ];
        if (a.BillingLatitude != null && a.BillingLongitude != null) {
            return GeoNamesWeatherService.getWeather(a.BillingLatitude, a.BillingLongitude, null);
        }
        if (a.ShippingLatitude != null && a.ShippingLongitude != null) {
            return GeoNamesWeatherService.getWeather(a.ShippingLatitude, a.ShippingLongitude, null);
        }
        String q = firstNonBlank(join(a.BillingCity, a.BillingCountry), join(a.ShippingCity, a.ShippingCountry));
        if (q == null) {
            throw new GeoNamesWeatherService.WeatherException('Sorry this account has no location (billing/shipping coordinates or city).');
        }
        GeoNamesWeatherService.GeoLocation loc = GeoNamesWeatherService.geocode(q);
        return GeoNamesWeatherService.getWeather(loc.lat, loc.lng, loc);
    }

    /** for the home page when browser geolocation is unavailable: location stored on the User record. */
    public static GeoNamesWeatherService.WeatherData resolveForCurrentUser() {
        User u = [SELECT Latitude, Longitude, City, Country FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.Latitude != null && u.Longitude != null) {
            return GeoNamesWeatherService.getWeather(u.Latitude, u.Longitude, null);
        }
        String q = join(u.City, u.Country);
        if (q == null) {
            throw new GeoNamesWeatherService.WeatherException('Sorry, no location found on your user profile.');
        }
        GeoNamesWeatherService.GeoLocation loc = GeoNamesWeatherService.geocode(q);
        return GeoNamesWeatherService.getWeather(loc.lat, loc.lng, loc);
    }

    private static String join(String city, String country) {
        if (String.isBlank(city)) return null;
        return String.isBlank(country) ? city : city + ', ' + country;
    }

    private static String firstNonBlank(String a, String b) {
        return a != null ? a : b;
    }
}
