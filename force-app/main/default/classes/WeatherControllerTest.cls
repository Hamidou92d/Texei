@IsTest
private class WeatherControllerTest {

    private class GeoNamesMock implements HttpCalloutMock {
        private Boolean noStation;
        GeoNamesMock(Boolean noStation) { this.noStation = noStation; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String url = req.getEndpoint();
            if (url.contains('/searchJSON')) {
                res.setBody('{"totalResultsCount":1,"geonames":[{"name":"Marseille","countryName":"France","lat":"43.29695","lng":"5.38107"}]}');
            } else if (url.contains('/findNearByWeatherJSON')) {
                res.setBody(noStation
                    ? '{"status":{"message":"no weather station found","value":15}}'
                    : '{"weatherObservation":{"temperature":"18","humidity":72,"windSpeed":"10","weatherCondition":"light rain","clouds":"broken clouds","cloudsCode":"BKN","stationName":"Marseille Provence","datetime":"2026-09-20 10:00:00"}}');
            } else {
                res.setBody('{"geonames":[{"name":"Nîmes","countryName":"France"}]}');
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Account a = new Account(Name = 'Test Account', BillingCity = 'Marseille', BillingCountry = 'France');
        insert a;
        insert new Contact(LastName = 'Doe', AccountId = a.Id, Email = 'doe@example.com');
    }

    @IsTest
    static void cityQueryReturnsWeather() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        GeoNamesWeatherService.WeatherData w = WeatherController.getWeatherByQuery('Marseille');
        Test.stopTest();
        Assert.areEqual('Marseille', w.locationName);
        Assert.areEqual(18, w.temperature.intValue());
        Assert.areEqual(72, w.humidity);
        Assert.areEqual(18.5, w.windSpeedKmh);
        Assert.areEqual('rain', w.iconKey);
    }

    @IsTest
    static void coordinatesQueryReturnsWeather() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        GeoNamesWeatherService.WeatherData w = WeatherController.getWeatherByQuery('43.29, 5.37');
        Test.stopTest();
        Assert.areEqual('Nîmes', w.locationName); // reverse lookup mock
    }

    @IsTest
    static void invalidInputsRaiseFriendlyErrors() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(true));
        Test.startTest();
        try { WeatherController.getWeatherByQuery(' '); Assert.fail(); } catch (AuraHandledException e) { Assert.isNotNull(e.getMessage()); }
        try { WeatherController.getWeatherByCoordinates(120, 0); Assert.fail(); } catch (AuraHandledException e) { Assert.isTrue(e.getMessage().contains('Invalid')); }
        try { WeatherController.getWeatherByQuery('1,1'); Assert.fail(); } catch (AuraHandledException e) { Assert.isTrue(e.getMessage().contains('GeoNames')); }
        Test.stopTest();
    }

    @IsTest
    static void accountWeatherFallsBackToCity() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        Assert.areEqual('Marseille', WeatherController.getWeatherForAccount(a.Id).locationName);
        Test.stopTest();
    }

    @IsTest
    static void sendReportToAccountContactsUpdatesField() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Account a = [SELECT Id FROM Account LIMIT 1];
        Test.startTest();
        WeatherNotificationService.SendResult r = WeatherController.sendReport(a.Id, 43.29, 5.38, 'Marseille');
        Test.stopTest();
        Assert.areEqual(1, r.recipientCount);
        Assert.areEqual('contacts', r.audience);
        Assert.isNotNull([SELECT Last_Weather_Report_Sent__c FROM Account WHERE Id = :a.Id].Last_Weather_Report_Sent__c);
        Assert.isNotNull(WeatherController.getLastReportSent(a.Id));
    }

    @IsTest
    static void sendReportToUsersUpdatesCurrentUser() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        WeatherNotificationService.SendResult r = WeatherController.sendReport(null, 43.29, 5.38, 'Marseille');
        Test.stopTest();
        Assert.areEqual('users', r.audience);
        Assert.isTrue(r.recipientCount >= 1);
    }

    // ---- WeatherLocationResolver.resolveForAccount
    @IsTest
    static void accountUsesBillingCoordinatesWhenPresent() {
        Account a = new Account(Name = 'Coords Account', BillingLatitude = 43.30, BillingLongitude = 5.40);
        insert a;
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        GeoNamesWeatherService.WeatherData w = WeatherController.getWeatherForAccount(a.Id);
        Test.stopTest();
        Assert.areEqual('Nîmes', w.locationName); // reverse-geocoded: a coordinates lookup carries no known place name
    }

    @IsTest
    static void accountUsesShippingCoordinatesWhenNoBilling() {
        Account a = new Account(Name = 'Shipping Coords Account', ShippingLatitude = 43.31, ShippingLongitude = 5.41);
        insert a;
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        GeoNamesWeatherService.WeatherData w = WeatherController.getWeatherForAccount(a.Id);
        Test.stopTest();
        Assert.areEqual('Nîmes', w.locationName);
    }

    @IsTest
    static void accountWithNoLocationThrowsFriendlyError() {
        Account a = new Account(Name = 'No Location Account');
        insert a;
        try {
            WeatherController.getWeatherForAccount(a.Id);
            Assert.fail('Expected an exception for an account with no location at all.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('location'));
        }
    }

    @IsTest
    static void accountWithNoContactsThrowsFriendlyError() {
        Account a = new Account(Name = 'No Contacts Account', BillingCity = 'Marseille', BillingCountry = 'France');
        insert a;
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        try {
            WeatherController.sendReport(a.Id, 43.29, 5.38, 'Marseille');
            Assert.fail('Expected an exception for an account with no contacts.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('contact'));
        }
        Test.stopTest();
    }

    // ---- WeatherLocationResolver.resolveForCurrentUser

    @IsTest
    static void currentUserFallsBackToProfileCity() {
        update new User(Id = UserInfo.getUserId(), City = 'Marseille', Country = 'France');
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        Test.startTest();
        GeoNamesWeatherService.WeatherData w = WeatherController.getWeatherForCurrentUser();
        Test.stopTest();
        Assert.areEqual('Marseille', w.locationName); // geocode() carries the known place name through
    }

    @IsTest
    static void currentUserWithNoLocationThrowsFriendlyError() {
        update new User(Id = UserInfo.getUserId(), City = null, Country = null, Latitude = null, Longitude = null);
        try {
            WeatherController.getWeatherForCurrentUser();
            Assert.fail('Expected an exception when the user has no location at all.');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('location'));
        }
    }

    // ---- WeatherNotificationService.getLastReportSent: the "current user" branch ----

    @IsTest
    static void lastReportSentForCurrentUserDoesNotThrow() {
        // No assertion on the returned value (it depends on ambient org data) — this test
        // exists to exercise the User branch of getLastReportSent
        WeatherController.getLastReportSent(null);
    }

    @IsTest
    static void guestUserCannotSendReport() {
        Test.setMock(HttpCalloutMock.class, new GeoNamesMock(false));
        List<Profile> guestProfiles = [SELECT Id FROM Profile WHERE UserType = 'Guest' LIMIT 1];
        if (guestProfiles.isEmpty()) return; // no Experience Cloud site provisioned yet in this org — nothing to assert
        User guest = new User(
            ProfileId = guestProfiles[0].Id, LastName = 'Guest', Alias = 'guest', Email = 'guest@example.invalid',
            Username = 'guest' + DateTime.now().getTime() + '@example.invalid',
            TimeZoneSidKey = 'GMT', LocaleSidKey = 'en_US', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
        );
        insert guest;
        System.runAs(guest) {
            try {
                WeatherController.sendReport(null, 43.29, 5.38, 'Marseille');
                Assert.fail('Guest users must not be able to send reports.');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void iconMapping() {
        Assert.areEqual('storm', GeoNamesWeatherService.resolveIcon('thunderstorm', null, null));
        Assert.areEqual('snow', GeoNamesWeatherService.resolveIcon('light snow', null, null));
        Assert.areEqual('fog', GeoNamesWeatherService.resolveIcon('mist', null, null));
        Assert.areEqual('sunny', GeoNamesWeatherService.resolveIcon('n/a', 'clear sky', 'CLR'));
        Assert.areEqual('partly', GeoNamesWeatherService.resolveIcon('n/a', 'few clouds', 'FEW'));
        Assert.areEqual('cloudy', GeoNamesWeatherService.resolveIcon('n/a', 'overcast', null));
        Assert.areEqual('unknown', GeoNamesWeatherService.resolveIcon(null, null, null));
    }
}
