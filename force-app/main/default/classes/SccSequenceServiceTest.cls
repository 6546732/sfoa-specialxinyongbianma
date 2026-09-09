@IsTest
private class SccSequenceServiceTest {
    @IsTest
    static void issuesAndAdvancesASequence() {
        Account accountRecord = new Account(Name = '序列测试客户');
        insert accountRecord;
        insert new CreditCodeSequence__c(
            Category__c = SccConstants.CATEGORY_HONG_KONG,
            NextSeq__c = 39
        );

        Test.startTest();
        SccSequenceService.IssuedSequence issued = SccSequenceService.issue(
            ' hong_kong ',
            accountRecord.Id
        );
        Test.stopTest();

        System.assertEquals(SccConstants.CATEGORY_HONG_KONG, issued.category);
        System.assertEquals(39, issued.value);
        System.assertEquals('0039', issued.fourDigitValue);

        CreditCodeSequence__c refreshed = [
            SELECT NextSeq__c
            FROM CreditCodeSequence__c
            WHERE Category__c = :SccConstants.CATEGORY_HONG_KONG
        ];
        System.assertEquals(40, refreshed.NextSeq__c);
    }

    @IsTest
    static void keepsCategoriesIndependent() {
        insert new List<CreditCodeSequence__c>{
            new CreditCodeSequence__c(Category__c = SccConstants.CATEGORY_MACAU, NextSeq__c = 26),
            new CreditCodeSequence__c(Category__c = SccConstants.CATEGORY_FOREIGN, NextSeq__c = 86)
        };

        SccSequenceService.IssuedSequence macau = SccSequenceService.issue(
            SccConstants.CATEGORY_MACAU,
            null
        );

        System.assertEquals('0026', macau.fourDigitValue);
        System.assertEquals(
            86,
            [SELECT NextSeq__c FROM CreditCodeSequence__c
             WHERE Category__c = :SccConstants.CATEGORY_FOREIGN].NextSeq__c
        );
    }

    @IsTest
    static void rejectsMissingUnknownAndExhaustedSequences() {
        assertConfigurationError(null);
        assertConfigurationError('UNKNOWN');
        assertConfigurationError(SccConstants.CATEGORY_TAIWAN);

        insert new CreditCodeSequence__c(
            Category__c = SccConstants.CATEGORY_MILITARY,
            NextSeq__c = 10000
        );
        assertConfigurationError(SccConstants.CATEGORY_MILITARY);
    }

    private static void assertConfigurationError(String category) {
        Boolean thrown = false;
        try {
            SccSequenceService.issue(category, null);
        } catch (SccSequenceService.SequenceConfigurationException expected) {
            thrown = true;
        }
        System.assert(thrown, '应拒绝无效序列配置：' + category);
    }
}