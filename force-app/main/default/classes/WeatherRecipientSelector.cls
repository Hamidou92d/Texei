/**
 * Class that queries who should receive a weather report.
 */
public with sharing class WeatherRecipientSelector {

    public static List<Id> getAccountContactIds(Id accountId) {
        List<Id> ids = new List<Id>();
        for (Contact c : [
            SELECT Id FROM Contact
            WHERE AccountId = :accountId AND Email != null AND IsEmailBounced = false
            WITH USER_MODE
        ]) {
            ids.add(c.Id);
        }
        return ids;
    }

    public static List<Id> getActiveUserIds(Integer maxRecipients) {
        List<Id> ids = new List<Id>();
        for (User u : [
            SELECT Id FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Email != null
            LIMIT :maxRecipients
        ]) {
            ids.add(u.Id);
        }
        return ids;
    }
}
