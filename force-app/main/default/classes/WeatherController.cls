/**
 * @AuraEnabled layer for the weatherWidget LWC 
 */

public with sharing class WeatherController {

    @AuraEnabled
    public static GeoNamesWeatherService.WeatherData getWeatherByQuery(String query) {
        try {
            return WeatherLocationResolver.resolveByQuery(query);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static GeoNamesWeatherService.WeatherData getWeatherByCoordinates(Decimal latitude, Decimal longitude) {
        try {
            return GeoNamesWeatherService.getWeather(latitude, longitude, null);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static GeoNamesWeatherService.WeatherData getWeatherForAccount(Id accountId) {
        try {
            return WeatherLocationResolver.resolveForAccount(accountId);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static GeoNamesWeatherService.WeatherData getWeatherForCurrentUser() {
        try {
            return WeatherLocationResolver.resolveForCurrentUser();
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static Datetime getLastReportSent(Id recordId) {
        return WeatherNotificationService.getLastReportSent(recordId);
    }

    @AuraEnabled
    public static WeatherNotificationService.SendResult sendReport(Id recordId, Decimal latitude, Decimal longitude, String locationLabel) {
        try {
            return WeatherNotificationService.sendReport(recordId, latitude, longitude, locationLabel);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    private static AuraHandledException wrap(Exception e) {
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
