public without sharing class SccSequenceService {
    private static final Integer MAX_FOUR_DIGIT_SEQUENCE = 9999;

    public static IssuedSequence issue(String category, Id accountId) {
        String normalizedCategory = normalizeCategory(category);

        List<CreditCodeSequence__c> candidates = [
            SELECT Id, Category__c, NextSeq__c
            FROM CreditCodeSequence__c
            WHERE Category__c = :normalizedCategory
            LIMIT 1
            FOR UPDATE
        ];
        if (candidates.isEmpty()) {
            throw new SequenceConfigurationException('缺少序列配置：' + normalizedCategory);
        }

        CreditCodeSequence__c sequenceRecord = candidates[0];
        if (sequenceRecord.NextSeq__c == null
            || sequenceRecord.NextSeq__c < 1
            || sequenceRecord.NextSeq__c > MAX_FOUR_DIGIT_SEQUENCE) {
            throw new SequenceConfigurationException(
                '序列 ' + normalizedCategory + ' 的下一可用值必须在 1 到 9999 之间。'
            );
        }

        Integer issuedValue = sequenceRecord.NextSeq__c.intValue();
        sequenceRecord.NextSeq__c = issuedValue + 1;
        sequenceRecord.LastIssuedAt__c = System.now();
        sequenceRecord.LastIssuedAccount__c = accountId;
        // Sequence allocation is an internal atomic operation. Run this update in
        // system mode so callers do not need direct edit access to the counter and
        // audit fields; UI services must enforce access to Account fields separately.
        Database.update(sequenceRecord, AccessLevel.SYSTEM_MODE);

        IssuedSequence result = new IssuedSequence();
        result.category = normalizedCategory;
        result.value = issuedValue;
        result.fourDigitValue = String.valueOf(issuedValue).leftPad(4, '0');
        return result;
    }

    @TestVisible
    private static String normalizeCategory(String category) {
        if (String.isBlank(category)) {
            throw new SequenceConfigurationException('序列类别不能为空。');
        }
        String normalized = category.trim().toUpperCase();
        if (!SccConstants.SEQUENCE_CATEGORIES.contains(normalized)) {
            throw new SequenceConfigurationException('不支持的序列类别：' + normalized);
        }
        return normalized;
    }

    public class IssuedSequence {
        public String category { get; set; }
        public Integer value { get; set; }
        public String fourDigitValue { get; set; }
    }

    public class SequenceConfigurationException extends Exception {}
}