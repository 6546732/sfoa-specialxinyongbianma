public without sharing class SccGenerationService {
    private SccGenerationService() {}

    public static Result generate(SccRuleEngine.Context context, Id accountId) {
        SccRuleEngine.Decision decision = SccRuleEngine.resolve(context);
        Result result = new Result();
        result.sequenceCategory = decision.sequenceCategory;
        List<SccTerritoryRule__mdt> formats = [SELECT Prefix__c, UseRegistrationNumber__c
            FROM SccTerritoryRule__mdt WHERE Active__c = true AND Territory__c = :decision.territory];
        if (formats.size() != 1 || String.isBlank(formats[0].Prefix__c)
            || !Pattern.matches('^[A-Z]{1,3}$', formats[0].Prefix__c)) {
            throw new GenerationException('地区格式配置缺失、重复或前缀无效。');
        }
        String prefix = formats[0].Prefix__c;
        String statusCode;
        if (decision.territory == 'MAINLAND') {
            String statusName = String.isBlank(context.organizationStatus) ? '存续' : context.organizationStatus;
            List<SccOrganizationStatusRule__mdt> statuses = [SELECT StatusCode__c
                FROM SccOrganizationStatusRule__mdt WHERE Active__c = true AND StatusName__c = :statusName];
            if (statuses.size() != 1 || String.isBlank(statuses[0].StatusCode__c)
                || !Pattern.matches('^[A-Z]{2}$', statuses[0].StatusCode__c)) {
                throw new GenerationException('组织状态配置缺失、重复或状态码无效。');
            }
            statusCode = statuses[0].StatusCode__c;
        }

        if (formats[0].UseRegistrationNumber__c && String.isNotBlank(context.businessRegistrationNumber)) {
            String registrationNumber = normalizeRegistrationNumber(context.businessRegistrationNumber);
            result.codeBody = prefix + registrationNumber;
        } else {
            SccSequenceService.IssuedSequence issued = SccSequenceService.issue(
                decision.sequenceCategory,
                accountId
            );
            result.sequenceValue = issued.value;
            if (new Set<String>{'HONG_KONG','MACAU','TAIWAN'}.contains(decision.territory)) {
                result.codeBody = prefix + issued.fourDigitValue;
            }
            else if (decision.territory == 'FOREIGN') {
                result.codeBody = prefix + decision.countryCode + issued.fourDigitValue;
            } else if (decision.isMilitary) {
                result.codeBody = prefix + decision.regionCode + decision.militaryIndustryCode
                    + decision.branchCode + issued.fourDigitValue + statusCode;
            } else {
                result.codeBody = prefix + decision.regionCode + decision.industryCode
                    + issued.fourDigitValue + statusCode;
            }
        }

        result.finalCode = SccCodeGenerator.appendCheckCharacter(result.codeBody);
        return result;
    }

    @TestVisible
    private static String normalizeRegistrationNumber(String rawValue) {
        if (String.isBlank(rawValue)) throw new GenerationException('商业登记号码为空。');
        String normalized = rawValue.trim().toUpperCase();
        if (!Pattern.matches('^[0-9A-Z]+$', normalized)) {
            throw new GenerationException('商业登记号码只能包含数字和英文字母；请先人工确认空格或符号。');
        }
        return normalized;
    }

    public class Result {
        public String codeBody;
        public String finalCode;
        public String sequenceCategory;
        public Integer sequenceValue;
    }

    public class GenerationException extends Exception {}
}