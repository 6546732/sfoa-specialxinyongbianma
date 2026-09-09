@IsTest
private class SccGenerationServiceTest {
    @IsTest
    static void metadataFormatsSupportRegistrationAndStatus() {
        SccRuleEngine.Context macau = context('澳门公司','澳门',null,null,null);
        macau.businessRegistrationNumber='00123456';
        System.assertEquals('SMC00123456', SccGenerationService.generate(macau,null).codeBody);
        System.assertEquals(26, sequence(SccConstants.CATEGORY_MACAU));
        SccRuleEngine.Context taiwan = context('台湾公司','台湾',null,null,null);
        taiwan.businessRegistrationNumber='00123456';
        System.assertEquals('STW00123456', SccGenerationService.generate(taiwan,null).codeBody);
        SccRuleEngine.Context mainland = context('注册中企业','中国','江苏','南京','制造业');
        mainland.organizationStatus='注册中';
        System.assert(SccGenerationService.generate(mainland,null).codeBody.endsWith('CC'));
    }
    @TestSetup
    static void sequences() {
        insert new List<CreditCodeSequence__c>{
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_HONG_KONG, NextSeq__c=39),
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_MACAU, NextSeq__c=26),
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_TAIWAN, NextSeq__c=1),
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_FOREIGN, NextSeq__c=86),
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_SPECIAL_UNIT, NextSeq__c=1),
            new CreditCodeSequence__c(Category__c=SccConstants.CATEGORY_MILITARY, NextSeq__c=1)
        };
    }

    @IsTest
    static void hongKongRegistrationPreservesZeroAndDoesNotConsumeSequence() {
        SccRuleEngine.Context value = context('香港公司', '香港', null, null, null);
        value.businessRegistrationNumber = '0690133';
        SccGenerationService.Result result = SccGenerationService.generate(value, null);
        System.assertEquals('SHK06901334', result.finalCode);
        System.assertEquals(null, result.sequenceValue);
        System.assertEquals(39, sequence(SccConstants.CATEGORY_HONG_KONG));
    }

    @IsTest
    static void generatesRegionalAndForeignCodes() {
        configureRules();
        SccGenerationService.Result hongKong = SccGenerationService.generate(context('香港客户','香港',null,null,null), null);
        System.assertEquals('SHK0039F', hongKong.finalCode);
        System.assertEquals('SMC0026N', SccGenerationService.generate(context('澳门客户','澳门',null,null,null), null).finalCode);
        System.assertEquals('SJP00866', SccGenerationService.generate(context('日本客户','日本',null,null,null), null).finalCode);
        System.assertEquals('SSG0087D', SccGenerationService.generate(context('新加坡客户','新加坡',null,null,null), null).finalCode);
    }

    @IsTest
    static void generatesMainlandNormalAndMilitaryCodes() {
        configureRules();
        SccGenerationService.Result normal = SccGenerationService.generate(
            context('上海制造企业','中国','上海市','上海市','制造业'), null);
        System.assertEquals(18, normal.finalCode.length());
        System.assert(normal.finalCode.startsWith('SCN3101CZ00'));

        SccGenerationService.Result military = SccGenerationService.generate(
            context('贵州警官职业学院','中国','贵州省','贵阳市',null), null);
        System.assertEquals(18, military.finalCode.length());
        System.assert(military.finalCode.startsWith('SCN5201WS07'));
    }

    @IsTest
    static void rejectsRegistrationPunctuation() {
        Boolean thrown = false;
        try { SccGenerationService.normalizeRegistrationNumber('12-34'); }
        catch (SccGenerationService.GenerationException expected) { thrown = true; }
        System.assert(thrown);
    }

    private static SccRuleEngine.Context context(String name, String country, String state, String city, String industry) {
        SccRuleEngine.Context value = new SccRuleEngine.Context();
        value.name=name; value.billingCountry=country; value.billingState=state;
        value.billingCity=city; value.industry=industry;
        return value;
    }

    private static Decimal sequence(String category) {
        return [SELECT NextSeq__c FROM CreditCodeSequence__c WHERE Category__c=:category].NextSeq__c;
    }

    private static void configureRules() {
        SccRuleEngine.testRegionCodes.put('上海|上海', '3101');
        SccRuleEngine.testRegionCodes.put('贵州|贵阳', '5201');
        SccRuleEngine.testIndustryCodes.put('制造业', 'CZ00');
        SccRuleEngine.testCountryCodes.put('日本', 'JP');
        SccRuleEngine.testCountryCodes.put('新加坡', 'SG');
    }
}