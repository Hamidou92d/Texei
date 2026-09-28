/**
 * Owns the "send a weather report" domain: who gets it (via WeatherRecipientSelector),
 * what it says (via WeatherEmailBuilder), sending it, and recording when it was sent.
 */
public with sharing class WeatherNotificationService {

    public class SendResult {
        @AuraEnabled public Integer recipientCount;
        @AuraEnabled public Datetime sentAt;
        @AuraEnabled public String audience; // 'contacts' | 'users'
    }

    private static final Integer MAX_USER_RECIPIENTS = 100;

    public static Datetime getLastReportSent(Id recordId) {
        try {
            if (recordId != null && recordId.getSObjectType() == Account.SObjectType) {
                return [SELECT Last_Weather_Report_Sent__c FROM Account WHERE Id = :recordId WITH USER_MODE LIMIT 1]
                    .Last_Weather_Report_Sent__c;
            }
            return [SELECT Last_Weather_Report_Sent__c FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1]
                .Last_Weather_Report_Sent__c;
        } catch (Exception e) {
            return null; 
        }
    }

    /**
     * recordId = Account Id  -> sends to the account's related contacts (with an email)
     * recordId = null        -> sends to the active standard users of the org
     */
    public static SendResult sendReport(Id recordId, Decimal latitude, Decimal longitude, String locationLabel) {
        if (UserInfo.getUserType() == 'Guest') {
            throw new GeoNamesWeatherService.WeatherException('Sending weather reports is not available on the public page.');
        }

        GeoNamesWeatherService.WeatherData w = GeoNamesWeatherService.getWeather(latitude, longitude, null);
        if (String.isBlank(w.locationName) || w.locationName.contains(',')) {
            w.locationName = String.isBlank(locationLabel) ? w.locationName : locationLabel;
        }

        Boolean forAccount = recordId != null && recordId.getSObjectType() == Account.SObjectType;
        List<Id> targets = forAccount
            ? WeatherRecipientSelector.getAccountContactIds(recordId)
            : WeatherRecipientSelector.getActiveUserIds(MAX_USER_RECIPIENTS);

        if (targets.isEmpty()) {
            throw new GeoNamesWeatherService.WeatherException(
                forAccount ? 'This account has no contact with an email address.' : 'No active user to notify.'
            );
        }

        String subject = WeatherEmailBuilder.buildSubject(w);
        String html = WeatherEmailBuilder.buildHtml(w);
        String plain = WeatherEmailBuilder.buildPlain(w);

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (Id target : targets) {
            Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
            m.setTargetObjectId(target);
            m.setSaveAsActivity(false);
            m.setSubject(subject);
            m.setHtmlBody(html);
            m.setPlainTextBody(plain);
            mails.add(m);
        }
        // allOrNothing = false: one address failing (bounced, invalid...) must not
        // silently block delivery to every other recipient in the same batch.
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(mails, false);
        Integer sentCount = 0;
        List<String> failures = new List<String>();
        for (Messaging.SendEmailResult res : results) {
            if (res.isSuccess()) {
                sentCount++;
            } else {
                for (Messaging.SendEmailError err : res.getErrors()) {
                    failures.add(err.getMessage());
                }
            }
        }
        if (sentCount == 0) {
            throw new GeoNamesWeatherService.WeatherException(
                'No e-mail could be sent. ' + (failures.isEmpty() ? '' : failures[0])
            );
        }

        Datetime now = Datetime.now();
        if (forAccount) {
            update as user new Account(Id = recordId, Last_Weather_Report_Sent__c = now);
        } else {
            update as user new User(Id = UserInfo.getUserId(), Last_Weather_Report_Sent__c = now);
        }

        SendResult r = new SendResult();
        r.recipientCount = sentCount;
        r.sentAt = now;
        r.audience = forAccount ? 'contacts' : 'users';
        return r;
    }
}
