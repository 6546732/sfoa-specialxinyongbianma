@IsTest
private class SccRuleEngineTest {
    @IsTest
    static void metadataMilitaryRulesOverrideAndRequireContext() {
        configureRules();
        SccRuleEngine.testMilitaryRules = new List<SccMilitaryRule__mdt>{
            new SccMilitaryRule__mdt(Keyword__c='海军', ContextKeywords__c='医院;疗养',
                MilitaryIndustryCode__c='WH', BranchCode__c='06')};
        SccRuleEngine.Decision hospital = resolve('海军疗养中心','中国','上海','上海',null);
        System.assertEquals('WH', hospital.militaryIndustryCode);
        System.assertEquals('06', hospital.branchCode, '配置必须优先于硬编码军种判断');
        SccRuleEngine.Context research = context('海军研究中心','中国','上海','上海',null);
        research.aiMilitaryIndustryCode='WR';
        System.assertEquals('WR', SccRuleEngine.resolve(research).militaryIndustryCode,
            '上下文未匹配不能使用医疗规则');
    }

    @IsTest
    static void deployedMetadataCoversNewMappings() {
        System.assertEquals('WH', resolve('海军医院','中国','江苏','南京','医疗').militaryIndustryCode);
        System.assertEquals('WS', resolve('空军训练基地','CN','湖北','武汉',null).militaryIndustryCode);
        System.assertEquals('JZ00', resolve('金融客户','中国','浙江','杭州','金融业').industryCode);
        System.assertEquals('4501', resolve('广西医院','中国','广西','南宁',null).regionCode);
        System.assertEquals('6590', resolve('白杨市医院','中国','新疆','白杨市',null).regionCode);
        System.assertEquals('US', resolve('美国客户','US',null,null,null).countryCode);
    }
    @IsTest
    static void resolvesTerritoriesAndConfiguredRules() {
        configureRules();
        System.assertEquals('HONG_KONG', resolve('客户', '中国', '香港特别行政区', null, null).territory);
        System.assertEquals('MACAU', resolve('客户', 'MO', null, null, null).territory);
        System.assertEquals('TAIWAN', resolve('客户', 'Taiwan', null, null, null).territory);

        SccRuleEngine.Decision foreignResult = resolve('日本客户', 'Japan', null, null, null);
        System.assertEquals('FOREIGN', foreignResult.territory);
        System.assertEquals('JP', foreignResult.countryCode);

        SccRuleEngine.Decision normalResult = resolve('上海制造企业', '中国', '上海市', '上海市', '制造业');
        System.assertEquals('3101', normalResult.regionCode);
        System.assertEquals('CZ00', normalResult.industryCode);
        System.assertEquals(SccConstants.CATEGORY_SPECIAL_UNIT, normalResult.sequenceCategory);

        SccRuleEngine.Decision hospital = resolve('上海中心医院', '中国', '上海', '上海', null);
        System.assertEquals('QZ00', hospital.industryCode);

        SccRuleEngine.Decision beijingDistrict = resolve(
            '中国人民解放军空军总医院', '中国', '北京市', '北京市海淀区', null);
        System.assertEquals('1101', beijingDistrict.regionCode);
        System.assertEquals('WH', beijingDistrict.militaryIndustryCode);
        System.assertEquals('03', beijingDistrict.branchCode);
    }

    @IsTest
    static void appliesFixedMilitaryMappings() {
        configureRules();
        SccRuleEngine.Decision police = resolve('贵州警官职业学院', '中国', '贵州省', '贵阳市', null);
        System.assert(police.isMilitary);
        System.assertEquals('WS', police.militaryIndustryCode);
        System.assertEquals('07', police.branchCode);

        SccRuleEngine.Decision corps = resolve('新疆生产建设兵团医院', '中国', '新疆维吾尔自治区', '乌鲁木齐市', null);
        System.assert(corps.isMilitary);
        System.assertEquals('WH', corps.militaryIndustryCode);
        System.assertEquals('01', corps.branchCode);
    }

    @IsTest
    static void rejectsUnknownRequiredMappings() {
        Boolean thrown = false;
        try {
            resolve('未知客户', '未知国家', null, null, null);
        } catch (SccRuleEngine.RuleException expected) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @IsTest
    static void coversMissingDataAndAiMilitaryValidation() {
        configureRules();
        assertRuleError(context('无国家客户', null, null, null, null));
        assertRuleError(context('无地区客户', '中国', '未知省', '未知市', '制造业'));
        assertRuleError(context('无行业客户', '中国', '上海', '上海', '未知行业'));

        SccRuleEngine.Context military = context('海军研究中心', '中国', '上海', '上海', null);
        military.aiMilitary = true;
        military.aiMilitaryIndustryCode = 'WR';
        SccRuleEngine.Decision decision = SccRuleEngine.resolve(military);
        System.assertEquals('WR', decision.militaryIndustryCode);
        System.assertEquals('02', decision.branchCode);
    }

    private static void assertRuleError(SccRuleEngine.Context value) {
        Boolean thrown = false;
        try { SccRuleEngine.resolve(value); }
        catch (SccRuleEngine.RuleException expected) { thrown = true; }
        System.assert(thrown);
    }

    private static SccRuleEngine.Decision resolve(String name, String country, String state, String city, String industry) {
        return SccRuleEngine.resolve(context(name, country, state, city, industry));
    }

    private static SccRuleEngine.Context context(String name, String country, String state, String city, String industry) {
        SccRuleEngine.Context value = new SccRuleEngine.Context();
        value.name=name; value.billingCountry=country; value.billingState=state;
        value.billingCity=city; value.industry=industry;
        return value;
    }

    private static void configureRules() {
        SccRuleEngine.testRegionCodes.put('上海|上海', '3101');
        SccRuleEngine.testRegionCodes.put('贵州|贵阳', '5201');
        SccRuleEngine.testRegionCodes.put('新疆维吾尔|乌鲁木齐', '6501');
        SccRuleEngine.testRegionCodes.put('北京|北京', '1101');
        SccRuleEngine.testIndustryCodes.put('制造业', 'CZ00');
        SccRuleEngine.testCountryCodes.put('JAPAN', 'JP');
    }
}
