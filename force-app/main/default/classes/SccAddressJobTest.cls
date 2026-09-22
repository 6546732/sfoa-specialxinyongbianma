@IsTest
private class SccAddressJobTest {
    private static Account customer(String street) {
        SccAddressHandler.pauseDispatch=true;
        Account value = new Account(Name='地址补全测试客户'+street,BillingStreet=street,BillingCountry='中国');
        value.put('jingyingfanwei__c','软件开发及技术服务');
        insert value;
        return value;
    }
    private static Id running(Id accountId) {
        SccAddressLookup__c row=[SELECT Id,Status__c FROM SccAddressLookup__c WHERE Account__c=:accountId LIMIT 1];
        row.Status__c='RUNNING'; update row; return row.Id;
    }
    private static SccAddressLookup__c audit(Id accountId) {
        return [SELECT Status__c,Reason__c,Method__c,Sources__c,Detail__c FROM SccAddressLookup__c WHERE Account__c=:accountId LIMIT 1];
    }
    @IsTest static void fillsStreetWithoutCalloutAndDoesNotTouchCode() {
        Account value=customer('广东省深圳市南山区科技园');
        value.xinyongdaima__c='KEEP'; update value;
        Id job=running(value.Id);
        Test.startTest(); System.enqueueJob(new SccAddressJob(job)); Test.stopTest();
        Account actual=[SELECT BillingState,BillingCity,xinyongdaima__c FROM Account WHERE Id=:value.Id];
        System.assertEquals('广东省',actual.BillingState);
        System.assertEquals('深圳市',actual.BillingCity);
        System.assertEquals('KEEP',actual.xinyongdaima__c);
        System.assertEquals('STREET',audit(value.Id).Method__c);
        System.assertEquals('地址识别成功',audit(value.Id).Reason__c);
        System.assertEquals(1,[SELECT COUNT() FROM SccAddressLookup__c WHERE Reason__c='地址识别成功']);
        System.assertEquals(1,[SELECT COUNT() FROM SccAddressLookup__c WHERE Account__c=:value.Id]);
    }
    @IsTest static void queriesWebOnlyWhenNeeded() {
        Account value=customer('科技园20号'); Id job=running(value.Id);
        Test.setMock(HttpCalloutMock.class,new AddressMock('success',value.Id));
        Test.startTest(); System.enqueueJob(new SccAddressJob(job)); Test.stopTest();
        System.assertEquals('广东省',[SELECT BillingState FROM Account WHERE Id=:value.Id].BillingState);
        System.assertEquals('COMPLETED',audit(value.Id).Status__c);
        System.assert(audit(value.Id).Sources__c.contains('example.test'));
        System.assertEquals('联网查询成功',audit(value.Id).Reason__c);
    }
    @IsTest static void fillsFreeTradeZoneAndCanRetryAfterProvinceClearedAgain() {
        Account value=customer('中国（上海）自由贸易试验区临港新片区云汉路979号2楼');
        value.BillingCity='市辖区'; update value;
        String hash=SccAddressHandler.fingerprint(value);
        SccAddressLookup__c request=[SELECT Id,Status__c FROM SccAddressLookup__c
            WHERE Account__c=:value.Id AND Fingerprint__c=:hash LIMIT 1];
        request.Status__c='RUNNING'; update request;
        SccAddressJob.process(request.Id);
        Account actual=[SELECT Id,BillingState,BillingCity FROM Account WHERE Id=:value.Id];
        System.assertEquals('上海市',actual.BillingState);
        System.assertEquals('市辖区',actual.BillingCity,'Preserve the existing city value.');
        System.assertEquals('STREET',[SELECT Method__c FROM SccAddressLookup__c WHERE Id=:request.Id].Method__c);
        actual.BillingState=null; update actual;
        System.assertEquals(2,[SELECT COUNT() FROM SccAddressLookup__c WHERE Account__c=:value.Id AND Fingerprint__c=:hash]);
        System.assertEquals(1,[SELECT COUNT() FROM SccAddressLookup__c WHERE Account__c=:value.Id AND Fingerprint__c=:hash AND Status__c='PENDING']);
    }
    @IsTest static void rejectsDifferentCompany() { runWeb('other','NO_MATCH'); }
    @IsTest static void rejectsMissingSources() { runWeb('noSource','NO_MATCH'); }
    @IsTest static void preservesConcurrentEdit() {
        Account value=runWeb('edit','SKIPPED');
        System.assertEquals('浙江省',[SELECT BillingState FROM Account WHERE Id=:value.Id].BillingState);
    }
    @IsTest static void rejectsInvalidPair() { runWeb('badPair','NO_MATCH'); }
    @IsTest static void recordsHttpFailure() { runWeb('http','FAILED'); }
    @IsTest static void recordsJsonFailure() { runWeb('json','FAILED'); }
    @IsTest static void rejectsResponseWithoutActualSearch() { runWeb('noSearch','FAILED'); }
    @IsTest static void acceptsDocumentedRenameForAddressOnly() { runWeb('rename','COMPLETED'); }
    @IsTest static void rejectsRenameWithoutEvidence() { runWeb('unprovenRename','NO_MATCH'); }
    private static Account runWeb(String mode,String expected) {
        Account value=customer('园区'+mode); Id job=running(value.Id);
        Test.setMock(HttpCalloutMock.class,new AddressMock(mode,value.Id));
        Test.startTest(); System.enqueueJob(new SccAddressJob(job)); Test.stopTest();
        System.assertEquals(expected,audit(value.Id).Status__c,audit(value.Id).Detail__c);
        if (mode=='http' || mode=='json' || mode=='noSearch') System.assertEquals('联网调用失败',audit(value.Id).Reason__c);
        if (mode=='other' || mode=='noSource') System.assertEquals('未找到可靠资料',audit(value.Id).Reason__c);
        if (mode=='other') System.assert(audit(value.Id).Detail__c.contains('返回名称“另一客户”'));
        if (mode=='noSource') System.assert(audit(value.Id).Detail__c.contains('未提供可核验来源'));
        return value;
    }
    @IsTest static void batchesAndDeduplicatesUnrelatedUpdates() {
        SccAddressHandler.pauseDispatch=true;
        List<Account> values=new List<Account>();
        for(Integer i=0;i<200;i++) {
            Account value=new Account(Name='批量地址测试'+i,BillingStreet='深圳市南山区');
            value.put('jingyingfanwei__c','软件开发'); values.add(value);
        }
        insert values;
        System.assertEquals(200,[SELECT COUNT() FROM SccAddressLookup__c]);
        for(Account value:values) value.Description='无关更新';
        update values;
        System.assertEquals(200,[SELECT COUNT() FROM SccAddressLookup__c]);
        values[0].BillingStreet='北京市海淀区'; update values[0];
        System.assertEquals(201,[SELECT COUNT() FROM SccAddressLookup__c]);
        insert new Account(Name='经营范围为空');
        Account populated=new Account(Name='已有省市',BillingState='广东省',BillingCity='深圳市');
        populated.put('jingyingfanwei__c','软件开发'); insert populated;
        System.assertEquals(201,[SELECT COUNT() FROM SccAddressLookup__c]);
    }
    @IsTest static void skipsStaleRequestsAndExistingCityConflicts() {
        Account value=customer('深圳市南山区'); Id job=running(value.Id);
        value.put('jingyingfanwei__c',null); update value;
        SccAddressJob.process(job);
        System.assertEquals('SKIPPED',audit(value.Id).Status__c);
        Account conflict=customer('广东省深圳市南山区');
        conflict.BillingCity='杭州市'; update conflict;
        SccAddressLookup__c latest=[SELECT Id,Status__c FROM SccAddressLookup__c
            WHERE Account__c=:conflict.Id AND Fingerprint__c=:SccAddressHandler.fingerprint(conflict) LIMIT 1];
        latest.Status__c='RUNNING'; update latest;
        SccAddressJob.process(latest.Id);
        System.assertEquals(null,[SELECT BillingState FROM Account WHERE Id=:conflict.Id].BillingState);
    }
    @IsTest static void dispatcherClaimsBeforeCallingOut() {
        Account value=customer('北京市海淀区');
        Test.startTest();
        new SccAddressJob().execute((QueueableContext)null);
        Test.stopTest();
        System.assertEquals('COMPLETED',audit(value.Id).Status__c);
    }
    @IsTest static void scheduledSweepCanRunWithoutRequests() {
        SccAddressHandler.pauseDispatch=true;
        new SccAddressSweep().execute(null);
        System.assertEquals(0,[SELECT COUNT() FROM SccAddressLookup__c]);
    }
    @IsTest static void fillsCityFromStreetPreservingProvince() { cityOnly('广东省深圳市南山区','广东','STREET','COMPLETED'); }
    @IsTest static void fillsCityWithWebWhenStreetEmpty() { cityOnly(null,'广东省','WEB','COMPLETED'); }
    @IsTest static void queriesWebWhenStreetHasOnlyProvince() { cityOnly('广东省','广东省','WEB','COMPLETED'); }
    @IsTest static void rejectsExistingProvinceConflict() { cityOnly('广东省深圳市南山区','浙江省','STREET','NO_MATCH'); }
    private static void cityOnly(String street,String province,String method,String status) {
        SccAddressHandler.pauseDispatch=true;
        Account a=new Account(Name='仅缺城市测试',BillingState=province,BillingStreet=street,BillingCountry='中国');
        a.put('jingyingfanwei__c','软件开发'); insert a;
        Test.setMock(HttpCalloutMock.class,new AddressMock('success',a.Id));
        Id request=running(a.Id);
        Test.startTest(); SccAddressJob.process(request); Test.stopTest();
        Account actual=[SELECT BillingState,BillingCity FROM Account WHERE Id=:a.Id];
        System.assertEquals(province,actual.BillingState,'Never normalize or overwrite existing province.');
        System.assertEquals(status=='COMPLETED'?'深圳市':null,actual.BillingCity);
        System.assertEquals(status,audit(a.Id).Status__c);
        System.assertEquals(status=='NO_MATCH'?'省市冲突或无法核验':method=='STREET'?'地址识别成功':'联网查询成功',audit(a.Id).Reason__c);
        System.assertEquals(method,audit(a.Id).Method__c);
        System.assertEquals(1,[SELECT COUNT() FROM SccAddressLookup__c WHERE Account__c=:a.Id],'No recursive task after filling city.');
    }
    private class AddressMock implements HttpCalloutMock {
        String mode; Id accountId;
        AddressMock(String mode,Id accountId) { this.mode=mode;this.accountId=accountId; }
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('callout:DeepSeek_Core_Business/responses',request.getEndpoint());
            Map<String,Object> body=(Map<String,Object>)JSON.deserializeUntyped(request.getBody());
            System.assertEquals('auto',body.get('tool_choice'));
            System.assert(String.valueOf(body.get('input')).contains('软件开发'));
            if(mode=='edit') update new Account(Id=accountId,BillingState='浙江省');
            HttpResponse response=new HttpResponse(); response.setStatusCode(mode=='http'?503:200);
            Map<String,Object> payload=new Map<String,Object>{'identityConfirmed'=>true,'exactNameMatch'=>true,
                'matchedCompanyName'=>mode=='other'?'另一客户':[SELECT Name FROM Account WHERE Id=:accountId].Name,
                'billingCountry'=>'中国','billingState'=>'广东省','billingCity'=>mode=='badPair'?'杭州市':'深圳市',
                'sources'=>mode=='noSource'?new List<Object>():new List<Object>{new Map<String,Object>{'name'=>'公司官网','url'=>'https://example.test/address'}}};
            if (mode=='rename' || mode=='unprovenRename') {
                payload.put('previousCompanyName',payload.get('matchedCompanyName'));
                payload.put('matchedCompanyName','地址补全测试企业新名称');
                payload.put('exactNameMatch',false);
                payload.put('identityEvidenceSourceUrl',mode=='rename'?'https://example.test/address':'');
            }
            response.setBody(mode=='json'?'broken':JSON.serialize(new Map<String,Object>{'output_text'=>JSON.serialize(payload),
                'output'=>mode=='noSearch'?new List<Object>():new List<Object>{new Map<String,Object>{'type'=>'web_search_call','status'=>'completed'}}}));
            return response;
        }
    }
}
