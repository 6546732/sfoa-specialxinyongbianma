@IsTest
private class SccAddressResolverTest {
    @IsTest static void recognizesConfiguredAddresses() {
        assertAddress('广东省深圳市南山区科技园', '广东省', '深圳市');
        assertAddress('广东深圳南山区科技园', '广东省', '深圳市');
        assertAddress('深圳市南山区科技园', '广东省', '深圳市');
        assertAddress('中国 北京市海淀区中关村', '北京市', '北京市');
        assertAddress('广西壮族自治区南宁市青秀区', '广西壮族自治区', '南宁市');
        assertAddress('广西南宁青秀区', '广西壮族自治区', '南宁市');
        assertAddress('吉林市船营区', '吉林省', '吉林市');
        assertAddress('吉林省某园区', '吉林省', null);
        assertAddress('海南藏族自治州共和县', '青海省', '海南藏族自治州');
        System.assertEquals(null, SccAddressResolver.resolve('北京路20号').province);
        System.assertEquals(null, SccAddressResolver.resolve('深圳大厦20楼').province);
        System.assertEquals(null, SccAddressResolver.resolve('鼓楼区中山路').province);
        System.assertEquals(null, SccAddressResolver.resolve('广东省杭州市西湖区').province);
        System.assertEquals(null, SccAddressResolver.validatePair('广东', '杭州').province);
    }
    @IsTest static void respectsAmbiguityAndMetadataAliases() {
        SccAddressResolver.testRules = new List<SccRegionRule__mdt>{
            new SccRegionRule__mdt(ProvinceName__c='甲省',CityName__c='甲城市',Aliases__c='同名市;甲城旧称'),
            new SccRegionRule__mdt(ProvinceName__c='乙省',CityName__c='乙城市',Aliases__c='同名市')};
        System.assertEquals(null, SccAddressResolver.resolve('同名市新区').province);
        assertAddress('甲城旧称新区', '甲省', '甲城市');
    }
    private static void assertAddress(String street, String province, String city) {
        SccAddressResolver.Match result = SccAddressResolver.resolve(street);
        System.assertEquals(province, result.province, street);
        System.assertEquals(city, result.city, street);
    }
}
