public without sharing class SccAddressHandler {
    public static Boolean pauseDispatch = false;
    private static Boolean dispatched = false;

    public static Boolean eligible(Account value) {
        return String.isBlank(value.BillingState) && String.isNotBlank((String)value.get('jingyingfanwei__c'));
    }

    public static String fingerprint(Account value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(JSON.serialize(
            new List<String>{value.Name, value.BillingStreet, value.BillingCountry, value.BillingCity,
                value.BillingState, (String)value.get('jingyingfanwei__c')}))));
    }

    public static void capture(List<Account> values, Map<Id,Account> oldValues) {
        Map<String,SccAddressLookup__c> pending = new Map<String,SccAddressLookup__c>();
        for (Account value : values) {
            if (!eligible(value)) continue;
            String hash = fingerprint(value);
            if (oldValues != null && hash == fingerprint(oldValues.get(value.Id))) continue;
            String key = String.valueOf(value.Id) + ':' + hash;
            pending.put(key, new SccAddressLookup__c(Account__c=value.Id,RequestKey__c=key,
                Fingerprint__c=hash,Status__c='PENDING',Detail__c='等待地址识别；无法识别时联网查询'));
        }
        if (pending.isEmpty()) return;
        Set<String> keys = pending.keySet();
        for (SccAddressLookup__c existing : (List<SccAddressLookup__c>)Database.queryWithBinds(
            'SELECT RequestKey__c FROM SccAddressLookup__c WHERE RequestKey__c IN :keys',
            new Map<String,Object>{'keys'=>keys}, AccessLevel.SYSTEM_MODE))
            pending.remove(existing.RequestKey__c);
        if (pending.isEmpty()) return;
        Database.insert(pending.values(), AccessLevel.SYSTEM_MODE);
        // Durable requests survive exhausted queueable slots; scheduled sweep resumes them.
        if (!pauseDispatch && !dispatched && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new SccAddressJob());
            dispatched = true;
        }
    }
}
