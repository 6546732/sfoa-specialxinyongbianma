public without sharing class SccRuleEngine {
    @TestVisible private static Map<String, String> testRegionCodes = new Map<String, String>();
    @TestVisible private static Map<String, String> testIndustryCodes = new Map<String, String>();
    @TestVisible private static Map<String, String> testCountryCodes = new Map<String, String>();
    @TestVisible private static List<SccMilitaryRule__mdt> testMilitaryRules;
    private SccRuleEngine() {}

    public static Decision resolve(Context input) {
        if (input == null) throw new RuleException('缺少客户资料。');

        String territory = classifyTerritory(input.billingCountry, input.billingState);
        Decision result = new Decision();
        result.territory = territory;

        if (territory == 'HONG_KONG') {
            result.sequenceCategory = SccConstants.CATEGORY_HONG_KONG;
            return result;
        }
        if (territory == 'MACAU') {
            result.sequenceCategory = SccConstants.CATEGORY_MACAU;
            return result;
        }
        if (territory == 'TAIWAN') {
            result.sequenceCategory = SccConstants.CATEGORY_TAIWAN;
            return result;
        }
        if (territory == 'FOREIGN') {
            result.countryCode = findCountryCode(input.billingCountry);
            if (String.isBlank(result.countryCode)) {
                throw new RuleException('国家无法映射为 ISO2 代码。');
            }
            result.sequenceCategory = SccConstants.CATEGORY_FOREIGN;
            return result;
        }

        result.regionCode = findRegionCode(input.billingState, input.billingCity);
        if (String.isBlank(result.regionCode)) {
            throw new RuleException('省份和城市无法映射为四位行政区划码。');
        }

        MilitaryDecision military = classifyMilitary(input);
        if (military.isMilitary) {
            result.isMilitary = true;
            result.militaryIndustryCode = military.industryCode;
            result.branchCode = military.branchCode;
            result.sequenceCategory = SccConstants.CATEGORY_MILITARY;
            if (String.isBlank(result.militaryIndustryCode) || String.isBlank(result.branchCode)) {
                throw new RuleException('军队客户的军事行业或军种无法可靠确定。');
            }
        } else {
            result.industryCode = isHospital(input.name)
                ? findIndustryCode('卫生和社会工作') : findIndustryCode(input.industry);
            if (String.isBlank(result.industryCode)) {
                throw new RuleException('行业无法映射为四位行业码。');
            }
            result.sequenceCategory = SccConstants.CATEGORY_SPECIAL_UNIT;
        }
        return result;
    }

    @TestVisible
    private static String classifyTerritory(String country, String state) {
        String joined = normalize(country) + '|' + normalize(state);
        if (containsAny(joined, new List<String>{'台湾', '臺灣', 'TAIWAN'})
            || isCode(country, state, new Set<String>{'TW'})) return 'TAIWAN';
        if (containsAny(joined, new List<String>{'香港', 'HONGKONG'})
            || isCode(country, state, new Set<String>{'HK'})) return 'HONG_KONG';
        if (containsAny(joined, new List<String>{'澳门', '澳門', 'MACAU', 'MACAO'})
            || isCode(country, state, new Set<String>{'MO'})) return 'MACAU';
        if (containsAny(normalize(country), new List<String>{'中国', '中國', 'CHINA', '中华人民共和国'})
            || new Set<String>{'CN','CHN'}.contains(normalize(country))) {
            return 'MAINLAND';
        }
        if (String.isBlank(country)) {
            throw new RuleException('国家为空，无法判定地区。');
        }
        return 'FOREIGN';
    }

    private static Boolean isCode(String country, String state, Set<String> codes) {
        return codes.contains(normalize(country)) || codes.contains(normalize(state));
    }

    private static String findRegionCode(String state, String city) {
        if (String.isBlank(state) || String.isBlank(city)) return null;
        String lookupCity = city;
        String normalizedState = normalizeLocation(state);
        if (new Set<String>{'北京','天津','上海','重庆'}.contains(normalizedState)) {
            // Four-digit administrative codes stop at prefecture level. Districts of a
            // direct-administered municipality therefore use the municipality code.
            lookupCity = state;
        }
        String testValue = testRegionCodes.get(normalizedState + '|' + normalizeLocation(lookupCity));
        if (Test.isRunningTest() && String.isNotBlank(testValue)) return testValue;
        for (SccRegionRule__mdt rule : [
            SELECT ProvinceName__c, CityName__c, Aliases__c, RegionCode__c
            FROM SccRegionRule__mdt
            WHERE Active__c = true
            ORDER BY Priority__c DESC NULLS LAST
        ]) {
            if (matches(rule.ProvinceName__c, null, state)
                && matches(rule.CityName__c, rule.Aliases__c, lookupCity)
                && Pattern.matches('^[0-9]{4}$', rule.RegionCode__c)) {
                return rule.RegionCode__c;
            }
        }
        return null;
    }

    private static String findIndustryCode(String industry) {
        if (String.isBlank(industry)) return null;
        String testValue = testIndustryCodes.get(normalize(industry));
        if (Test.isRunningTest() && String.isNotBlank(testValue)) return testValue;
        for (SccIndustryRule__mdt rule : [
            SELECT SalesforceValue__c, Aliases__c, IndustryCode__c
            FROM SccIndustryRule__mdt
            WHERE Active__c = true
            ORDER BY Priority__c DESC NULLS LAST
        ]) {
            if (matches(rule.SalesforceValue__c, rule.Aliases__c, industry)
                && Pattern.matches('^[0-9A-Z]{4}$', rule.IndustryCode__c)) {
                return rule.IndustryCode__c.toUpperCase();
            }
        }
        return null;
    }

    private static String findCountryCode(String country) {
        String testValue = testCountryCodes.get(normalize(country));
        if (Test.isRunningTest() && String.isNotBlank(testValue)) return testValue;
        for (SccCountryRule__mdt rule : [
            SELECT CountryName__c, Aliases__c, Iso2Code__c
            FROM SccCountryRule__mdt
            WHERE Active__c = true
        ]) {
            if (matches(rule.CountryName__c, rule.Aliases__c, country)
                && Pattern.matches('^[A-Za-z]{2}$', rule.Iso2Code__c)) {
                return rule.Iso2Code__c.toUpperCase();
            }
        }
        return null;
    }

    private static MilitaryDecision classifyMilitary(Context input) {
        String name = normalize(input.name);
        List<SccMilitaryRule__mdt> configuredRules = Test.isRunningTest() && testMilitaryRules != null
            ? testMilitaryRules : [SELECT Keyword__c, ContextKeywords__c, MilitaryIndustryCode__c,
                BranchCode__c FROM SccMilitaryRule__mdt WHERE Active__c = true
                ORDER BY Priority__c DESC NULLS LAST, DeveloperName ASC];
        for (SccMilitaryRule__mdt rule : configuredRules) {
            if (String.isBlank(rule.Keyword__c) || !name.contains(normalize(rule.Keyword__c))) continue;
            if (String.isNotBlank(rule.ContextKeywords__c)
                && !containsAny(name, rule.ContextKeywords__c.split('[,，;；\\n]+'))) continue;
            MilitaryDecision configured = new MilitaryDecision();
            configured.isMilitary = true;
            configured.industryCode = validMilitaryIndustry(rule.MilitaryIndustryCode__c);
            configured.branchCode = validBranch(rule.BranchCode__c);
            if (configured.industryCode == null || configured.branchCode == null) {
                throw new RuleException('匹配的军事元数据规则包含无效的军事行业码或军种码。');
            }
            return configured;
        }
        Boolean forced = containsAny(name, new List<String>{
            '解放军','部队','军队','武警','军区','军分区','联勤','陆军','海军','空军','火箭军',
            '战略支援','军事航天','网络空间','总参','总政','总后','总装','国防','司令部','军医大学',
            '兵团','警官','警察','公安','司法警察'
        });
        MilitaryDecision result = new MilitaryDecision();
        result.isMilitary = forced || input.aiMilitary == true;
        if (!result.isMilitary) return result;

        Boolean education = containsAny(name, new List<String>{'学院','学校','大学'});
        Boolean hospital = isHospital(name);
        Boolean research = containsAny(name, new List<String>{'科研','研究院','实验室'});
        Boolean manufacturing = containsAny(name, new List<String>{'军工','装备制造','制造'});

        if (containsAny(name, new List<String>{'警官','警察','公安','司法警察','武警'})) {
            result.industryCode = education ? 'WS' : 'WA';
            result.branchCode = '07';
            return result;
        }
        if (name.contains('兵团')) {
            result.industryCode = hospital ? 'WH' : education ? 'WS' : research ? 'WR' : manufacturing ? 'WM' : 'WA';
            result.branchCode = '01';
            return result;
        }

        result.industryCode = hospital ? 'WH' : validMilitaryIndustry(input.aiMilitaryIndustryCode);
        result.branchCode = inferBranch(name);
        if (String.isBlank(result.branchCode)) result.branchCode = validBranch(input.aiBranchCode);
        if (hospital && String.isBlank(result.branchCode)) result.branchCode = '01';
        return result;
    }

    private static String inferBranch(String name) {
        if (containsAny(name, new List<String>{'海军'})) return '02';
        if (containsAny(name, new List<String>{'空军'})) return '03';
        if (containsAny(name, new List<String>{'战略支援','军事航天','网络空间'})) return '04';
        if (containsAny(name, new List<String>{'火箭军'})) return '05';
        if (containsAny(name, new List<String>{'联勤'})) return '06';
        if (containsAny(name, new List<String>{'陆军'})) return '01';
        return null;
    }

    private static String validMilitaryIndustry(String value) {
        String normalized = normalize(value);
        return new Set<String>{'WH','WS','WM','WR','WA'}.contains(normalized) ? normalized : null;
    }

    private static String validBranch(String value) {
        String normalized = normalize(value);
        return new Set<String>{'01','02','03','04','05','06','07'}.contains(normalized) ? normalized : null;
    }

    private static Boolean isHospital(String value) {
        return containsAny(normalize(value), new List<String>{'医院','医疗','卫生院','诊所'});
    }

    private static Boolean matches(String primary, String aliases, String actual) {
        String target = normalizeLocation(actual);
        if (target == normalizeLocation(primary)) return true;
        if (String.isBlank(aliases)) return false;
        for (String aliasValue : aliases.split('[,，;；\\n]+')) {
            if (target == normalizeLocation(aliasValue)) return true;
        }
        return false;
    }

    private static String normalizeLocation(String value) {
        String normalized = normalize(value);
        Map<String, String> provinces = new Map<String, String>{
            '广西壮族自治区'=>'广西','广西壮族'=>'广西', '宁夏回族自治区'=>'宁夏','宁夏回族'=>'宁夏',
            '新疆维吾尔自治区'=>'新疆','新疆维吾尔'=>'新疆'};
        if (provinces.containsKey(normalized)) return provinces.get(normalized);
        return normalized.replaceAll('(特别行政区|自治州|自治区|地区|省|市|盟)$', '');
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase().replaceAll('\\s+', '');
    }

    private static Boolean containsAny(String value, List<String> values) {
        for (String candidate : values) if (value.contains(normalize(candidate))) return true;
        return false;
    }

    public class Context {
        public String name;
        public String billingCountry;
        public String billingState;
        public String billingCity;
        public String industry;
        public String businessRegistrationNumber;
        public String organizationStatus;
        public Boolean aiMilitary;
        public String aiMilitaryIndustryCode;
        public String aiBranchCode;
    }

    public class Decision {
        public String territory;
        public Boolean isMilitary = false;
        public String regionCode;
        public String industryCode;
        public String militaryIndustryCode;
        public String branchCode;
        public String countryCode;
        public String sequenceCategory;
    }

    private class MilitaryDecision {
        Boolean isMilitary = false;
        String industryCode;
        String branchCode;
    }

    public class RuleException extends Exception {}
}
