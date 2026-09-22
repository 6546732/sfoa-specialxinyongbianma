/** Claim in a separate transaction, then call out, then recheck/lock before writing. */
public without sharing class SccAddressJob implements Queueable, Database.AllowsCallouts {
    private Id requestId;
    public SccAddressJob() {}
    public SccAddressJob(Id value) { requestId = value; }

    public static void sweep() {
        List<SccAddressLookup__c> abandoned = Database.queryWithBinds(
            'SELECT Id,Status__c,Detail__c FROM SccAddressLookup__c WHERE Status__c=\'RUNNING\' AND LastModifiedDate < :cutoff LIMIT 100',
            new Map<String,Object>{'cutoff'=>System.now().addHours(-1)}, AccessLevel.SYSTEM_MODE);
        for (SccAddressLookup__c row : abandoned) {
            row.Status__c='FAILED'; row.Detail__c='后台任务异常中断，请检查 Apex 作业；未自动重试联网。';
        }
        if (!abandoned.isEmpty()) Database.update(abandoned, AccessLevel.SYSTEM_MODE);
        dispatchNext();
    }

    public void execute(QueueableContext context) {
        if (requestId == null) {
            List<SccAddressLookup__c> pending = Database.queryWithBinds(
                'SELECT Id,Status__c FROM SccAddressLookup__c WHERE Status__c=\'PENDING\' LIMIT 1 FOR UPDATE',
                new Map<String,Object>(), AccessLevel.SYSTEM_MODE);
            if (pending.isEmpty()) return;
            pending[0].Status__c='RUNNING';
            Database.update(pending, AccessLevel.SYSTEM_MODE);
            System.enqueueJob(new SccAddressJob(pending[0].Id));
            return;
        }
        process(requestId);
        dispatchNext();
    }

    private static void dispatchNext() {
        if (!SccAddressHandler.pauseDispatch && Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()
            && !Database.queryWithBinds('SELECT Id FROM SccAddressLookup__c WHERE Status__c=\'PENDING\' LIMIT 1',
                new Map<String,Object>(), AccessLevel.SYSTEM_MODE).isEmpty())
            System.enqueueJob(new SccAddressJob());
    }

    @TestVisible private static void process(Id lookupId) {
        SccAddressLookup__c audit = (SccAddressLookup__c)Database.queryWithBinds(
            'SELECT Id,Account__c,Fingerprint__c,Status__c FROM SccAddressLookup__c WHERE Id=:lookupId',
            new Map<String,Object>{'lookupId'=>lookupId}, AccessLevel.SYSTEM_MODE)[0];
        if (audit.Status__c != 'RUNNING') return;
        try {
            List<Account> records = loadAccount(audit.Account__c, false);
            if (records.isEmpty() || !unchanged(records[0], audit)) {
                finish(audit,'SKIPPED','客户资料已变化、省市已完整或经营范围为空'); return;
            }
            Account original = records[0];
            SccAddressResolver.Match match = SccAddressResolver.resolve(original.BillingStreet);
            String method = 'STREET';
            Boolean matchedByRename = false;
            if (String.isBlank(match.province) || (String.isBlank(original.BillingCity) && String.isBlank(match.city))) {
                method = 'WEB';
                audit.Method__c=method;
                SccDeepSeekClient.ResearchResult result = SccDeepSeekClient.researchAddress(original);
                audit.Sources__c = JSON.serialize(result.sources);
                audit.Detail__c = result.notes;
                if (String.isNotBlank(result.previousCompanyName)
                    && original.Name.trim().equalsIgnoreCase(result.previousCompanyName.trim())
                    && String.isNotBlank(result.matchedCompanyName)
                    && String.isNotBlank(result.identityEvidenceSourceUrl) && result.sources != null) {
                    for (SccDeepSeekClient.Source source : result.sources)
                        if (source.url == result.identityEvidenceSourceUrl) matchedByRename = true;
                }
                List<String> rejected = new List<String>();
                if (result.identityConfirmed != true) rejected.add('AI未确认是同一客户主体');
                if (result.exactNameMatch != true && !matchedByRename) rejected.add('未确认登记全名匹配，且缺少更名证据');
                if (String.isBlank(result.matchedCompanyName)) rejected.add('未返回登记企业全名');
                else if (!original.Name.trim().equalsIgnoreCase(result.matchedCompanyName.trim()) && !matchedByRename)
                    rejected.add('返回名称“' + result.matchedCompanyName + '”与客户名称“' + original.Name + '”不一致');
                if (result.sources == null || result.sources.isEmpty()) rejected.add('未提供可核验来源');
                if (!rejected.isEmpty()) {
                    finish(audit,'NO_MATCH',String.join(rejected,'；')
                        + (String.isBlank(result.notes) ? '' : '。查询说明：' + result.notes)); return;
                }
                if (String.isBlank(result.billingCity)) {
                    finish(audit,'NO_MATCH','联网未提供可验证的城市'); return;
                }
                match = SccAddressResolver.validatePair(result.billingState, result.billingCity);
            }
            audit.Method__c=method;
            if (String.isBlank(match.province)) { finish(audit,'NO_MATCH',match.reason); return; }
            if (String.isNotBlank(original.BillingState)) {
                SccAddressResolver.Match existingProvince=SccAddressResolver.validatePair(original.BillingState,null);
                if (existingProvince.province != match.province) {
                    finish(audit,'NO_MATCH','识别结果与客户已有省份冲突或已有省份无法核验'); return;
                }
            }
            // Existing city is authoritative. A conflict must never be silently filled around.
            if (String.isNotBlank(original.BillingCity)) {
                SccAddressResolver.Match existing = SccAddressResolver.validatePair(match.province, original.BillingCity);
                if (String.isBlank(existing.province) || (String.isNotBlank(match.city) && existing.city != match.city)) {
                    finish(audit,'NO_MATCH','识别结果与客户已有城市冲突或已有城市无法核验'); return;
                }
            }
            if (String.isNotBlank(original.BillingCountry)
                && !new Set<String>{'中国','中國','CHINA','CN','CHN','中华人民共和国'}.contains(original.BillingCountry.trim().toUpperCase())) {
                finish(audit,'NO_MATCH','现有国家/地区不适用大陆省市配置，需人工核对'); return;
            }
            List<Account> current = loadAccount(original.Id, true);
            if (current.isEmpty() || !unchanged(current[0], audit)) {
                finish(audit,'SKIPPED','查询期间客户资料已变化，未写入过期结果'); return;
            }
            Account patch = new Account(Id=original.Id);
            if (String.isBlank(current[0].BillingState)) patch.BillingState=match.province;
            if (String.isBlank(current[0].BillingCity) && String.isNotBlank(match.city)) patch.BillingCity=match.city;
            Database.update(patch, AccessLevel.SYSTEM_MODE);
            audit.Province__c=match.province; audit.City__c=match.city;
            finish(audit,'COMPLETED',method == 'STREET' ? '根据开单街道和省市配置补齐空字段'
                : matchedByRename ? '根据联网更名证据确认同一主体，并通过省市配置核验后补齐空字段'
                : '根据联网来源及省市配置核验后补齐空字段');
        } catch (Exception error) {
            finish(audit,'FAILED',error.getMessage());
        }
    }

    private static Boolean unchanged(Account value, SccAddressLookup__c audit) {
        return SccAddressHandler.eligible(value) && SccAddressHandler.fingerprint(value) == audit.Fingerprint__c;
    }

    private static List<Account> loadAccount(Id accountId, Boolean lockRow) {
        return Database.queryWithBinds('SELECT Id,Name,BillingStreet,BillingState,BillingCity,BillingCountry,jingyingfanwei__c'
            + ' FROM Account WHERE Id=:accountId' + (lockRow ? ' FOR UPDATE' : ''),
            new Map<String,Object>{'accountId'=>accountId}, AccessLevel.SYSTEM_MODE);
    }

    private static void finish(SccAddressLookup__c audit, String status, String detail) {
        audit.Status__c=status;
        audit.Detail__c=String.isBlank(detail) ? status : detail.left(3000);
        Database.update(audit, AccessLevel.SYSTEM_MODE);
    }
}
