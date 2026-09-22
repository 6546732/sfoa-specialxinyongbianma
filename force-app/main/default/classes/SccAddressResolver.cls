/** Conservative address-prefix matching against the existing region metadata. */
public without sharing class SccAddressResolver {
    @TestVisible private static List<SccRegionRule__mdt> testRules;
    private static List<SccRegionRule__mdt> cachedRules;

    private static List<SccRegionRule__mdt> rules() {
        if (testRules != null) return testRules;
        if (cachedRules == null) cachedRules = [SELECT ProvinceName__c, CityName__c, Aliases__c
            FROM SccRegionRule__mdt WHERE Active__c = true];
        return cachedRules;
    }

    public class Match {
        public String province;
        public String city;
        public String reason;
    }

    public static Match resolve(String street) {
        String address = clean(street);
        if (address.startsWith('中华人民共和国')) address = address.substring(7);
        else if (address.startsWith('中国')) address = address.substring(2);
        Map<String, String> provinces = new Map<String, String>();
        Integer longest = 0;
        for (SccRegionRule__mdt rule : rules()) {
            for (String alias : provinceAliases(rule.ProvinceName__c)) {
                if (prefix(address, alias)) {
                    if (alias.length() > longest) { provinces.clear(); longest = alias.length(); }
                    if (alias.length() == longest) provinces.put(rule.ProvinceName__c, address.substring(longest));
                }
            }
        }
        Match result = new Match();
        if (provinces.size() > 1) { result.reason = '省份匹配存在歧义'; return result; }
        String province = provinces.isEmpty() ? null : new List<String>(provinces.keySet())[0];
        String remaining = province == null ? address : provinces.get(province);
        Integer provincePrefixLength = longest;
        Map<String, SccRegionRule__mdt> cities = new Map<String, SccRegionRule__mdt>();
        longest = 0;
        for (SccRegionRule__mdt rule : rules()) {
            for (String alias : cityAliases(rule)) {
                if (prefix(remaining, alias) || (alias.length() > provincePrefixLength && prefix(address, alias))) {
                    if (alias.length() > longest) { cities.clear(); longest = alias.length(); }
                    if (alias.length() == longest) cities.put(rule.ProvinceName__c + '|' + rule.CityName__c, rule);
                }
            }
        }
        if (cities.size() > 1) { result.reason = '城市匹配存在歧义'; return result; }
        if (cities.size() == 1) {
            SccRegionRule__mdt cityRule = cities.values()[0];
            if (province != null && province != cityRule.ProvinceName__c) {
                Boolean fullCityPrefix = false;
                for (String alias : cityAliases(cityRule)) {
                    if (alias.length() > provincePrefixLength && prefix(address, alias)) fullCityPrefix = true;
                }
                if (!fullCityPrefix) { result.reason = '街道中的省份与城市不对应'; return result; }
            }
            result.province = cityRule.ProvinceName__c;
            result.city = cityRule.CityName__c;
        } else if (province != null) {
            result.province = province;
            // Municipalities use the same value for province and city.
            if (new Set<String>{'北京市','上海市','天津市','重庆市'}.contains(province)) result.city = province;
        } else result.reason = '街道开头未识别到唯一省市';
        return result;
    }

    /** Validate returned/previous city against a specific configured province. */
    public static Match validatePair(String province, String city) {
        Match result = new Match();
        Set<String> matchingProvinces = new Set<String>();
        Set<String> matchingCities = new Set<String>();
        for (SccRegionRule__mdt rule : rules()) {
            if (!provinceAliases(rule.ProvinceName__c).contains(clean(province))) continue;
            matchingProvinces.add(rule.ProvinceName__c);
            if (String.isNotBlank(city) && cityAliases(rule).contains(clean(city))) matchingCities.add(rule.CityName__c);
        }
        if (matchingProvinces.size() != 1 || (String.isNotBlank(city) && matchingCities.size() != 1)) {
            result.reason = '省市不在现有配置中或对应关系不明确'; return result;
        }
        result.province = new List<String>(matchingProvinces)[0];
        if (matchingCities.size() == 1) result.city = new List<String>(matchingCities)[0];
        return result;
    }

    private static Set<String> provinceAliases(String raw) {
        String value = clean(raw);
        Set<String> aliases = new Set<String>{value};
        for (String suffix : new List<String>{'壮族自治区','回族自治区','维吾尔自治区','自治区','特别行政区','省','市'}) {
            if (value.endsWith(suffix)) aliases.add(value.substring(0, value.length() - suffix.length()));
        }
        aliases.remove('');
        return aliases;
    }

    private static Set<String> cityAliases(SccRegionRule__mdt rule) {
        String value = clean(rule.CityName__c);
        Set<String> aliases = new Set<String>{value};
        if (value.endsWith('市')) aliases.add(value.substring(0, value.length() - 1));
        if (String.isNotBlank(rule.Aliases__c)) {
            for (String alias : rule.Aliases__c.split(';')) if (String.isNotBlank(alias)) aliases.add(clean(alias));
        }
        aliases.remove('');
        return aliases;
    }

    private static Boolean prefix(String address, String token) {
        if (String.isBlank(token) || !address.startsWith(token)) return false;
        String rest = address.substring(token.length());
        // A place-name appearing in a road/building name isn't an administrative prefix.
        return !Pattern.matches('^(路|街|大街|大道|大厦|大廈|大楼|广场|廣場|花园|花園|公寓|小区|小區|酒店|饭店|號|号|[0-9]).*', rest);
    }

    private static String clean(String value) {
        return String.isBlank(value) ? '' : value.replaceAll('[\\s,，]+', '').trim();
    }
}
