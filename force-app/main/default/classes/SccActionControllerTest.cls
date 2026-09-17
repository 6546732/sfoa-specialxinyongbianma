@IsTest
private class SccActionControllerTest {
    @IsTest
    static void searchesSimilarCustomersIndependently() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='港澳台相似查询客户');
        insert value;
        Test.setMock(HttpCalloutMock.class, new DeepSeekMock());
        Test.startTest();
        List<SccDeepSeekClient.SimilarCustomer> matches = SccActionController.findSimilarCustomers(value.Id);
        Test.stopTest();
        System.assertEquals(0, matches.size());
    }
    @IsTest
    static void manuallyPreviewsAndWritesCodeWithAudit() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='手工编码客户');
        insert value;
        SccActionController.AccountView view = SccActionController.loadAccount(value.Id);
        System.assertEquals('手工编码客户', view.name);

        String finalCode = SccActionController.saveManual(value.Id, ' SHK30653538 ', null);
        System.assertEquals('SHK306535389', finalCode);
        System.assertEquals(finalCode, [SELECT xinyongdaima__c FROM Account WHERE Id=:value.Id].xinyongdaima__c);
        System.assertEquals('COMPLETED', [SELECT Status__c FROM CreditCodeGeneration__c WHERE Account__c=:value.Id].Status__c);
    }

    @IsTest
    static void researchesThenConfirmsHongKongRegistration() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='香港测试客户');
        insert value;
        Test.setMock(HttpCalloutMock.class, new DeepSeekMock());

        Test.startTest();
        SccDeepSeekClient.ResearchResult result = SccActionController.research(value.Id);
        String finalCode = SccActionController.generateFromResearch(
            value.Id,
            result.auditId,
            null,
            null,
            result.identityConfirmed,
            result.billingCountry,
            result.billingState,
            result.billingCity,
            result.industry,
            result.businessRegistrationNumber,
            result.isMilitary,
            result.militaryIndustryCode,
            result.branchCode,
            null
        );
        Test.stopTest();

        System.assertEquals('SHK06901334', finalCode);
        Account refreshed = [SELECT BillingCountry, Business_Registration_Number__c, xinyongdaima__c FROM Account WHERE Id=:value.Id];
        System.assertEquals('香港', refreshed.BillingCountry);
        System.assertEquals('0690133', refreshed.Business_Registration_Number__c);
        System.assertEquals(finalCode, refreshed.xinyongdaima__c);
    }

    @IsTest
    static void acceptsCachedObjectAndJsonParameterFormats() {
        SccActionController.bypassPermissionForTests = true;

        Account jsonAccount = new Account(Name='JSON 缓存页面客户');
        Account objectAccount = new Account(Name='对象缓存页面客户');
        Account auditAccount = new Account(Name='仅审计兜底客户');
        insert new List<Account>{jsonAccount, objectAccount, auditAccount};
        CreditCodeGeneration__c jsonAudit = readyAudit(jsonAccount.Id);
        CreditCodeGeneration__c objectAudit = readyAudit(objectAccount.Id);
        CreditCodeGeneration__c auditFallback = readyAudit(auditAccount.Id);
        SccDeepSeekClient.ResearchResult fallbackSelection = hkSelection('06886002');
        fallbackSelection.matchedCompanyName = auditAccount.Name;
        fallbackSelection.exactNameMatch = true;
        fallbackSelection.sources = officialResearch(auditAccount.Name).sources;
        auditFallback.AiResult__c = JSON.serialize(fallbackSelection);
        Database.insert(
            new List<CreditCodeGeneration__c>{jsonAudit, objectAudit, auditFallback},
            AccessLevel.SYSTEM_MODE
        );

        SccDeepSeekClient.ResearchResult jsonSelection = hkSelection('77254080');
        String jsonCode = SccActionController.generateFromResearch(
            jsonAccount.Id, jsonAudit.Id, null, JSON.serialize(jsonSelection),
            null, null, null, null, null, null, null, null, null, null
        );
        System.assertEquals('SHK77254080A', jsonCode);

        SccDeepSeekClient.ResearchResult objectSelection = hkSelection('62935578');
        String objectCode = SccActionController.generateFromResearch(
            objectAccount.Id, objectAudit.Id, objectSelection, null,
            null, null, null, null, null, null, null, null, null, null
        );
        System.assertEquals('SHK629355784', objectCode);

        String auditCode = SccActionController.generateFromResearch(
            auditAccount.Id, auditFallback.Id, null, null,
            null, null, null, null, null, null, null, null, null, null
        );
        System.assertEquals('SHK068860027', auditCode);
    }

    private static CreditCodeGeneration__c readyAudit(Id accountId) {
        return new CreditCodeGeneration__c(
            Account__c=accountId,
            Mode__c='AI_LOOKUP',
            Status__c='READY'
        );
    }

    @IsTest
    static void officialCodeUsesTrustedAuditAndNoSequence() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='万帮星星充电科技有限公司');
        insert value;
        CreditCodeSequence__c sequence = new CreditCodeSequence__c(Category__c='SPECIAL_UNIT', NextSeq__c=7);
        insert sequence;
        SccDeepSeekClient.ResearchResult verified = officialResearch(value.Name);
        CreditCodeGeneration__c audit = readyAudit(value.Id);
        audit.AiResult__c = JSON.serialize(verified);
        insert audit;
        String result = SccActionController.generateFromResearch(value.Id, audit.Id,
            null, null, null, null, null, null, null, null, null, null, null, null);
        System.assertEquals('913204123137449322', result);
        System.assertEquals(result, [SELECT xinyongdaima__c FROM Account WHERE Id=:value.Id].xinyongdaima__c);
        System.assertEquals(7, [SELECT NextSeq__c FROM CreditCodeSequence__c WHERE Id=:sequence.Id].NextSeq__c);
        CreditCodeGeneration__c completed = [SELECT Status__c, FinalCode__c, SequenceValue__c FROM CreditCodeGeneration__c WHERE Id=:audit.Id];
        System.assertEquals('COMPLETED', completed.Status__c);
        System.assertEquals(result, completed.FinalCode__c);
        System.assertEquals(null, completed.SequenceValue__c);
    }

    @IsTest
    static void rejectsUnmatchedMissingSourceAndInvalidChecksum() {
        SccDeepSeekClient.ResearchResult result = officialResearch('目标公司');
        System.assertEquals(null, SccActionController.matchedOfficialCode('其他公司', result));
        result.exactNameMatch = false;
        System.assertEquals(null, SccActionController.matchedOfficialCode('目标公司', result));
        result.exactNameMatch = true;
        result.unifiedSocialCreditCode = '913204123137449323';
        System.assertEquals(null, SccActionController.matchedOfficialCode('目标公司', result));
        result.unifiedSocialCreditCode = '913204123137449322';
        result.sources.clear();
        System.assertEquals(null, SccActionController.matchedOfficialCode('目标公司', result));
    }

    @IsTest
    static void explainsWhyOnlineCodeFallsBackToRules() {
        SccDeepSeekClient.ResearchResult result = officialResearch('舟山市档案馆（舟山市史志研究室）');
        SccActionController.describeCodeDecision('舟山市档案馆', result);
        System.assertEquals(false, result.officialCodeAccepted);
        System.assertEquals('内部编码规则', result.codeSource);
        System.assert(result.officialCodeRejectionReason.contains('不完全一致'));

        result = officialResearch('舟山市档案馆');
        SccActionController.describeCodeDecision('舟山市档案馆', result);
        System.assertEquals(true, result.officialCodeAccepted);
        System.assertEquals('联网查询（已核验统一社会信用代码）', result.codeSource);

        result = new SccDeepSeekClient.ResearchResult();
        result.isMilitary = false;
        result.branchCode = '01';
        SccActionController.normalizeCertainMilitaryCodes('中国人民解放军空军总医院', result);
        System.assertEquals(true, result.isMilitary);
        System.assertEquals('WH', result.militaryIndustryCode);
        System.assertEquals('03', result.branchCode);
    }

    @IsTest
    static void mismatchFallsBackAndDoesNotTrustBrowserCode() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='香港回退客户', BillingCountry='香港', Business_Registration_Number__c='0690133');
        insert value;
        SccDeepSeekClient.ResearchResult stored = officialResearch('其他公司');
        stored.billingCountry = '香港';
        CreditCodeGeneration__c audit = readyAudit(value.Id);
        audit.AiResult__c = JSON.serialize(stored);
        insert audit;
        SccDeepSeekClient.ResearchResult edited = officialResearch(value.Name);
        edited.billingCountry = '香港';
        String result = SccActionController.generateFromResearch(value.Id, audit.Id,
            edited, null, null, null, null, null, null, null, null, null, null, null);
        System.assertEquals('SHK06901334', result);
    }

    private static SccDeepSeekClient.ResearchResult officialResearch(String name) {
        SccDeepSeekClient.ResearchResult result = new SccDeepSeekClient.ResearchResult();
        result.matchedCompanyName = name;
        result.exactNameMatch = true;
        result.unifiedSocialCreditCode = '913204123137449322';
        SccDeepSeekClient.Source source = new SccDeepSeekClient.Source();
        source.name = '登记来源'; source.url = 'https://example.test/registry';
        result.sources = new List<SccDeepSeekClient.Source>{source};
        return result;
    }

    private static SccDeepSeekClient.ResearchResult hkSelection(String registrationNumber) {
        SccDeepSeekClient.ResearchResult result = new SccDeepSeekClient.ResearchResult();
        result.identityConfirmed=true;
        result.billingCountry='香港';
        result.businessRegistrationNumber=registrationNumber;
        result.isMilitary=false;
        return result;
    }

    private class DeepSeekMock implements HttpCalloutMock {
        private Boolean matched = true;
        DeepSeekMock() {}
        DeepSeekMock(Boolean matched) { this.matched = matched; }
        public HttpResponse respond(HttpRequest request) {
            System.assert(request.getEndpoint().contains('DeepSeek_Core_Business'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setBody(JSON.serialize(new Map<String,Object>{
                'output_text'=>JSON.serialize(new Map<String,Object>{
                    'identityConfirmed'=>true,
                    'exactNameMatch'=>matched,
                    'matchedCompanyName'=>matched ? '香港测试客户' : '其他公司',
                    'billingCountry'=>'香港',
                    'billingState'=>'香港特别行政区',
                    'billingCity'=>'香港',
                    'industry'=>'',
                    'businessRegistrationNumber'=>'0690133',
                    'isMilitary'=>false,
                    'militaryIndustryCode'=>'',
                    'branchCode'=>'',
                    'notes'=>'已核验',
                    'sources'=>new List<Object>{new Map<String,Object>{'name'=>'测试登记处','url'=>'https://example.test/hk'}}
                })
            }));
            return response;
        }
    }

    @IsTest
    static void previewsConfirmedHospitalWithoutConsumingSequence() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='中国人民解放军空军总医院');
        insert value;
        CreditCodeSequence__c counter = new CreditCodeSequence__c(Category__c='MILITARY', NextSeq__c=42);
        insert counter;
        SccDeepSeekClient.ResearchResult candidate = officialResearch('中国人民解放军空军特色医学中心');
        candidate.exactNameMatch = false;
        candidate.billingCountry = '中国';
        candidate.billingState = '北京市';
        candidate.billingCity = '北京市海淀区';
        candidate.isMilitary = true;
        candidate.branchCode = '01';
        CreditCodeGeneration__c audit = readyAudit(value.Id);
        audit.AiResult__c = JSON.serialize(candidate);
        insert audit;
        SccActionController.InternalPreview blocked = SccActionController.previewInternal(value.Id, audit.Id, JSON.serialize(candidate));
        System.assertEquals(null, blocked.finalCode);
        System.assert(blocked.error.contains('国家'));
        candidate.confirmedForInternal = true;
        SccActionController.InternalPreview result = SccActionController.previewInternal(value.Id, audit.Id, JSON.serialize(candidate));
        System.assertEquals(null, result.error);
        System.assert(result.finalCode.startsWith('SCN1101WH030042AC'));
        System.assert(result.explanation.contains('空军（03）'));
        System.assertEquals(42, [SELECT NextSeq__c FROM CreditCodeSequence__c WHERE Id=:counter.Id].NextSeq__c);
        System.assertEquals(null, [SELECT BillingCountry FROM Account WHERE Id=:value.Id].BillingCountry);
        String saved = SccActionController.generateFromResearch(value.Id, audit.Id, null, JSON.serialize(candidate),
            null,null,null,null,null,null,null,null,null,null);
        System.assertEquals(result.finalCode, saved);
        System.assertEquals(43, [SELECT NextSeq__c FROM CreditCodeSequence__c WHERE Id=:counter.Id].NextSeq__c);
    }

    @IsTest
    static void unmatchedResearchDoesNotWriteOrGenerateFromOtherCompany() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='香港测试客户');
        insert value;
        Test.setMock(HttpCalloutMock.class, new DeepSeekMock(false));
        Test.startTest();
        SccDeepSeekClient.ResearchResult result = SccActionController.research(value.Id);
        Account actual = [SELECT BillingCountry, Business_Registration_Number__c FROM Account WHERE Id=:value.Id];
        System.assertEquals(null, actual.BillingCountry);
        System.assertEquals(null, actual.Business_Registration_Number__c);
        System.assertEquals(0, result.autoFilledFields.size());
        Boolean rejected = false;
        try {
            SccActionController.generateFromResearch(value.Id, result.auditId, hkSelection('0690133'), null,
                null, null, null, null, null, null, null, null, null, null);
        } catch (AuraHandledException expected) { rejected = true; }
        System.assert(rejected, '不能使用其他企业资料生成客户编码');
        Test.stopTest();
        System.assertEquals(null, [SELECT xinyongdaima__c FROM Account WHERE Id=:value.Id].xinyongdaima__c);
    }

    @IsTest
    static void auditSnapshotPreservesValuesBeforeAutomaticFill() {
        SccActionController.bypassPermissionForTests = true;
        Account value = new Account(Name='香港测试客户');
        insert value;
        Test.setMock(HttpCalloutMock.class, new DeepSeekMock());
        Test.startTest();
        SccDeepSeekClient.ResearchResult result = SccActionController.research(value.Id);
        Test.stopTest();
        CreditCodeGeneration__c audit = [SELECT InputSnapshot__c FROM CreditCodeGeneration__c WHERE Id=:result.auditId];
        Map<String,Object> beforeFill = (Map<String,Object>)JSON.deserializeUntyped(audit.InputSnapshot__c);
        System.assertEquals(null, beforeFill.get('billingCountry'));
        System.assertEquals('香港', [SELECT BillingCountry FROM Account WHERE Id=:value.Id].BillingCountry);
    }
}
