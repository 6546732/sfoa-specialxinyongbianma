/** Explicit ID upload only; never scans all Accounts. */
public with sharing class SccAddressBulkController {
    @TestVisible private static Boolean bypassPermissionForTests = false;
    public class Row {
        @AuraEnabled public String inputId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String detail;
        @AuraEnabled public String reason;
        @AuraEnabled public Id requestId;
        @AuraEnabled public String province;
        @AuraEnabled public String city;
        @AuraEnabled public String method;
        @AuraEnabled public String sources;
    }
    private static void authorize() {
        if (!(Test.isRunningTest() && bypassPermissionForTests)
            && !FeatureManagement.checkPermission('Scc_Bulk_Address'))
            throw new AuraHandledException('需要“客户地址批量补全管理员”权限。');
        if (!Account.SObjectType.getDescribe().isUpdateable()
            || !Account.BillingState.getDescribe().isUpdateable()
            || !Account.BillingCity.getDescribe().isUpdateable())
            throw new AuraHandledException('需要客户及开单省市的编辑权限。');
    }
    @AuraEnabled public static List<Row> preview(String csv) { return prepare(csv, false); }
    @AuraEnabled public static List<Row> submit(String csv) { return prepare(csv, true); }
    private static List<Row> prepare(String csv, Boolean enqueue) {
        authorize();
        if (String.isBlank(csv) || csv.length() > 20000)
            throw new AuraHandledException('请上传仅含客户ID的一列CSV，最多300条。');
        List<Row> rows = new List<Row>();
        Set<Id> ids = new Set<Id>();
        Map<Id,Row> byId = new Map<Id,Row>();
        for (String line : csv.replace('\r','').replace('\uFEFF','').split('\n')) {
            String value = line.trim();
            if (value == '') continue;
            if (value.startsWith('"') && value.endsWith('"') && value.length()>1)
                value=value.substring(1,value.length()-1);
            if (rows.isEmpty() && (value.equalsIgnoreCase('Id') || value.equalsIgnoreCase('AccountId') || value=='客户ID')) continue;
            Row row = new Row(); row.inputId=value; rows.add(row);
            if (rows.size()>300) throw new AuraHandledException('每次最多上传300条客户ID，请拆分文件。');
            try {
                if (!Pattern.matches('[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?',value)) throw new IllegalArgumentException();
                Id accountId = (Id)value;
                if (accountId.getSObjectType()!=Account.SObjectType) throw new IllegalArgumentException();
                if (ids.contains(accountId)) { row.status='SKIPPED'; row.detail='文件内重复ID'; }
                else { ids.add(accountId); byId.put(accountId,row); row.status='SKIPPED'; row.detail='客户不存在或无权访问'; }
            } catch (Exception error) { row.status='INVALID'; row.detail='不是有效的客户ID；仅支持单列CSV'; }
        }
        if (rows.isEmpty()) throw new AuraHandledException('文件中没有客户ID。');
        List<Account> accounts = Database.queryWithBinds(
            'SELECT Id,Name,BillingState,BillingCity,BillingStreet,BillingCountry,jingyingfanwei__c FROM Account WHERE Id IN :ids'
            + (enqueue ? ' FOR UPDATE' : ''),new Map<String,Object>{'ids'=>ids},AccessLevel.USER_MODE);
        List<Account> eligible = new List<Account>();
        Set<String> keys = new Set<String>();
        Set<Id> editable = new Set<Id>();
        List<Id> visibleIds = new List<Id>();
        for (Account account : accounts) visibleIds.add(account.Id);
        for (Integer offset=0; offset<visibleIds.size(); offset+=200) {
            Set<Id> chunk=new Set<Id>();
            for(Integer i=offset; i<Math.min(offset+200,visibleIds.size()); i++) chunk.add(visibleIds[i]);
            for(UserRecordAccess access : [SELECT RecordId,HasEditAccess FROM UserRecordAccess
                WHERE UserId=:UserInfo.getUserId() AND RecordId IN :chunk]) {
                if(access.HasEditAccess) editable.add(access.RecordId);
            }
        }
        for (Account account : accounts) {
            Row row=byId.get(account.Id); row.name=account.Name;
            if (!editable.contains(account.Id)) row.detail='没有此客户的编辑权限';
            else if (String.isNotBlank(account.BillingState) && String.isNotBlank(account.BillingCity)) row.detail='开单省市已完整，不覆盖';
            else if (!SccAddressHandler.eligible(account)) row.detail='经营范围为空，不满足处理条件';
            else {
                row.status='READY'; row.detail=String.isBlank(account.BillingStreet)
                    ? '街道为空，将按客户名称联网查询' : '先识别街道，无法识别时联网查询';
                eligible.add(account); keys.add(String.valueOf(account.Id)+':'+SccAddressHandler.fingerprint(account));
            }
        }
        if (enqueue && !eligible.isEmpty()) {
            SccAddressHandler.capture(eligible,null);
            // Authorized Accounts only. The existing trigger queue may be owned by another user.
            for (SccAddressLookup__c audit : (List<SccAddressLookup__c>)Database.queryWithBinds(
                'SELECT Id,Account__c,Status__c,Reason__c,Detail__c FROM SccAddressLookup__c WHERE RequestKey__c IN :keys',
                new Map<String,Object>{'keys'=>keys},AccessLevel.SYSTEM_MODE)) {
                Row row=byId.get(audit.Account__c); row.requestId=audit.Id;
                row.status=audit.Status__c; row.detail=audit.Detail__c; row.reason=audit.Reason__c;
            }
        }
        return rows;
    }
    @AuraEnabled public static List<Row> progress(List<Id> requestIds) {
        authorize();
        if (requestIds==null || requestIds.size()>300) throw new AuraHandledException('查询请求不得超过300条。');
        List<SccAddressLookup__c> audits=Database.queryWithBinds(
            'SELECT Id,Account__c,Status__c,Reason__c,Detail__c,Province__c,City__c,Method__c,Sources__c FROM SccAddressLookup__c WHERE Id IN :ids',
            new Map<String,Object>{'ids'=>requestIds},AccessLevel.SYSTEM_MODE);
        Set<Id> accountIds=new Set<Id>();
        for (SccAddressLookup__c audit:audits) accountIds.add(audit.Account__c);
        Map<Id,Account> visible=new Map<Id,Account>((List<Account>)Database.queryWithBinds(
            'SELECT Id,Name FROM Account WHERE Id IN :ids',new Map<String,Object>{'ids'=>accountIds},AccessLevel.USER_MODE));
        List<Row> rows=new List<Row>();
        for (SccAddressLookup__c audit:audits) {
            if (!visible.containsKey(audit.Account__c)) continue;
            Row row=new Row(); row.requestId=audit.Id; row.inputId=String.valueOf(audit.Account__c);
            row.name=visible.get(audit.Account__c).Name; row.status=audit.Status__c; row.detail=audit.Detail__c; row.reason=audit.Reason__c;
            row.province=audit.Province__c; row.city=audit.City__c; row.method=audit.Method__c; row.sources=audit.Sources__c;
            rows.add(row);
        }
        return rows;
    }
}
