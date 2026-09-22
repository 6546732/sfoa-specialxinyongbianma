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
        List<SccAddressLookup__c> completedKeys = new List<SccAddressLookup__c>();
        for (SccAddressLookup__c existing : (List<SccAddressLookup__c>)Database.queryWithBinds(
            'SELECT Id,RequestKey__c,Status__c FROM SccAddressLookup__c WHERE RequestKey__c IN :keys',
            new Map<String,Object>{'keys'=>keys}, AccessLevel.SYSTEM_MODE)) {
            if (existing.Status__c == 'PENDING' || existing.Status__c == 'RUNNING') pending.remove(existing.RequestKey__c);
            else {
                // A later explicit address change can retry; old terminal audit remains intact.
                existing.RequestKey__c = null;
                completedKeys.add(existing);
            }
        }
        if (!completedKeys.isEmpty()) Database.update(completedKeys, AccessLevel.SYSTEM_MODE);
        if (pending.isEmpty()) return;
        Database.insert(pending.values(), AccessLevel.SYSTEM_MODE);
        // Durable requests survive exhausted queueable slots; scheduled sweep resumes them.
        if (!pauseDispatch && !dispatched && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new SccAddressJob());
            dispatched = true;
        }
    }
}
