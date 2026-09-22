@IsTest
private class SccAddressBulkControllerTest {
    private static List<Account> fixtures(Integer count) {
        SccAddressHandler.pauseDispatch=true;
        SccAddressBulkController.bypassPermissionForTests=true;
        List<Account> values=new List<Account>();
        for (Integer i=0;i<count;i++) {
            Account a=new Account(Name='批量地址测试'+i);
            a.put('jingyingfanwei__c','技术服务'); values.add(a);
        }
        insert values; return values;
    }
    @IsTest static void previewDoesNotEnqueueAndFiltersInput() {
        List<Account> values=fixtures(3);
        values[1].BillingState='上海市'; values[1].BillingCity='上海市'; values[2].put('jingyingfanwei__c',null); update values;
        Integer beforeCount=[SELECT COUNT() FROM SccAddressLookup__c];
        List<SccAddressBulkController.Row> rows=SccAddressBulkController.preview('Id\n"'+values[0].Id+'"\n'+values[0].Id+'\n'+values[1].Id+'\n'+values[2].Id+'\nBAD\n'+UserInfo.getUserId());
        System.assertEquals(6,rows.size()); System.assertEquals('READY',rows[0].status);
        System.assert(rows[0].detail.contains('街道为空'));
        System.assertEquals('SKIPPED',rows[1].status); System.assertEquals('SKIPPED',rows[2].status);
        System.assertEquals('SKIPPED',rows[3].status); System.assertEquals('INVALID',rows[4].status);
        System.assertEquals('INVALID',rows[5].status);
        System.assertEquals(beforeCount,[SELECT COUNT() FROM SccAddressLookup__c]);
    }
    @IsTest static void submits300AndReusesPendingRequests() {
        List<Account> values=fixtures(300);
        // Simulate existing customers without previously captured requests.
        delete [SELECT Id FROM SccAddressLookup__c];
        List<String> ids=new List<String>(); for(Account a:values) ids.add(String.valueOf(a.Id));
        String csv=String.join(ids,'\n');
        Test.startTest();
        List<SccAddressBulkController.Row> rows=SccAddressBulkController.submit(csv);
        List<SccAddressBulkController.Row> again=SccAddressBulkController.submit(csv);
        Test.stopTest();
        System.assertEquals(300,rows.size()); System.assertEquals(300,[SELECT COUNT() FROM SccAddressLookup__c]);
        System.assertEquals(rows[0].requestId,again[0].requestId);
        System.assertEquals('PENDING',rows[0].status);
        System.assertEquals('PENDING',SccAddressBulkController.progress(new List<Id>{rows[0].requestId})[0].status);
    }
    @IsTest static void rejectsOversizeAndMissingPermission() {
        SccAddressBulkController.bypassPermissionForTests=true;
        List<String> ids=new List<String>(); for(Integer i=0;i<301;i++) ids.add('BAD');
        Boolean rejected=false;
        try { SccAddressBulkController.preview(String.join(ids,'\n')); } catch(AuraHandledException e) { rejected=true; }
        System.assert(rejected);
        User isolated = new User(Alias='sccbulk',Email='sccbulk@example.invalid',
            EmailEncodingKey='UTF-8',LastName='Bulk permission test',LanguageLocaleKey='en_US',
            LocaleSidKey='en_US',TimeZoneSidKey='Asia/Shanghai',ProfileId=UserInfo.getProfileId(),
            Username='sccbulk.'+UserInfo.getOrganizationId()+'.'+System.now().getTime()+'@example.invalid');
        insert isolated;
        SccAddressBulkController.bypassPermissionForTests=false; rejected=false;
        System.runAs(isolated) {
            try { SccAddressBulkController.preview('BAD'); } catch(AuraHandledException e) { rejected=true; }
        }
        System.assert(rejected,'Permission must not be inherited from the test runner permission set.');
    }
    @IsTest static void submitRechecksEligibilityAfterPreview() {
        Account a=fixtures(1)[0]; String csv=String.valueOf(a.Id);
        System.assertEquals('READY',SccAddressBulkController.preview(csv)[0].status);
        a.BillingState='浙江省'; a.BillingCity='杭州市'; update a;
        System.assertEquals('SKIPPED',SccAddressBulkController.submit(csv)[0].status);
        System.assertEquals('浙江省',[SELECT BillingState FROM Account WHERE Id=:a.Id].BillingState);
    }
}
