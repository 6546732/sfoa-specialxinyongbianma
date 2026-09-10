// INSTALLATION STEP ONLY. This file is not run by installing the package.
// Replace null ONLY for categories missing in the destination org, using its
// next unused sequence (1..9999). Existing counters are never reset.
Map<String, Decimal> approvedNextValues = new Map<String, Decimal>{
    'SPECIAL_UNIT'=>null, 'MILITARY'=>null, 'HONG_KONG'=>null,
    'MACAU'=>null, 'TAIWAN'=>null, 'FOREIGN'=>null
};
Set<String> existing = new Set<String>();
for (CreditCodeSequence__c row : [SELECT Category__c FROM CreditCodeSequence__c]) {
    existing.add(row.Category__c);
}
List<CreditCodeSequence__c> missing = new List<CreditCodeSequence__c>();
for (String category : approvedNextValues.keySet()) {
    if (existing.contains(category)) continue;
    Decimal nextValue = approvedNextValues.get(category);
    System.assert(nextValue != null && nextValue >= 1 && nextValue <= 9999
        && nextValue == nextValue.setScale(0), '请先填写已确认的下一可用序号：' + category);
    missing.add(new CreditCodeSequence__c(Category__c=category, NextSeq__c=nextValue));
}
if (!missing.isEmpty()) insert missing;
System.debug('New sequence records: ' + missing.size());
