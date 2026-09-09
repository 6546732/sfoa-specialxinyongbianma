public with sharing class SccActionController {
    @TestVisible private static Boolean bypassPermissionForTests = false;
    @AuraEnabled(cacheable=true)
    public static AccountView loadAccount(Id accountId) {
        requireGeneratePermission();
        Account value = load(accountId, false);
        AccountView result = new AccountView();
        result.name = value.Name;
        result.billingCountry = value.BillingCountry;
        result.billingState = value.BillingState;
        result.billingCity = value.BillingCity;
        result.industry = value.Industry;
        result.businessRegistrationNumber = value.Business_Registration_Number__c;
        result.currentCode = value.xinyongdaima__c;
        result.canReplace = FeatureManagement.checkPermission('Scc_Replace_Existing_Code');
        return result;
    }

    @AuraEnabled
    public static SccDeepSeekClient.ResearchResult research(Id accountId) {
        requireGeneratePermission();
        Account value = load(accountId, false);
        SccDeepSeekClient.ResearchResult result;
        try {
            result = SccDeepSeekClient.research(value);
            normalizeCertainMilitaryCodes(value.Name, result);
            describeCodeDecision(value.Name, result);
            Account current = load(accountId, true);
            result.autoFilledFields = applyOnlyMissing(current, result);
            result.warnings = findConflicts(current, result);
            if (!result.autoFilledFields.isEmpty()) Database.update(current, AccessLevel.SYSTEM_MODE);
            CreditCodeGeneration__c audit = new CreditCodeGeneration__c(
                Account__c = accountId,
                Mode__c = 'AI_LOOKUP',
                Status__c = 'READY',
                InputSnapshot__c = snapshot(current),
                AiResult__c = JSON.serialize(result),
                SourceUrls__c = sourceUrls(result.sources)
            );
            Database.insert(audit, AccessLevel.SYSTEM_MODE);
            result.auditId = audit.Id;
            return result;
        } catch (Exception error) {
            Database.insert(new CreditCodeGeneration__c(
                Account__c = accountId,
                Mode__c = 'AI_LOOKUP',
                Status__c = 'FAILED',
                InputSnapshot__c = snapshot(value),
                ErrorMessage__c = abbreviate(error.getMessage(), 32768)
            ), AccessLevel.SYSTEM_MODE);
            throw new AuraHandledException(error.getMessage());
        }
    }

    @AuraEnabled
    public static List<SccDeepSeekClient.SimilarCustomer> findSimilarCustomers(Id accountId) {
        requireGeneratePermission();
        return SccDeepSeekClient.findSimilarCustomers(load(accountId, false));
    }

    @AuraEnabled
    public static String generateFromResearch(
        Id accountId,
        Id auditId,
        SccDeepSeekClient.ResearchResult selection,
        String selectionJson,
        Boolean identityConfirmed,
        String billingCountry,
        String billingState,
        String billingCity,
        String industry,
        String businessRegistrationNumber,
        Boolean isMilitary,
        String militaryIndustryCode,
        String branchCode,
        String replacementReason
    ) {
        requireGeneratePermission();
        CreditCodeGeneration__c audit = lockAudit(auditId, accountId);
        SccDeepSeekClient.ResearchResult effectiveSelection = selection;
        if (effectiveSelection == null && String.isNotBlank(selectionJson)) {
            try {
                effectiveSelection = (SccDeepSeekClient.ResearchResult)JSON.deserialize(
                    selectionJson,
                    SccDeepSeekClient.ResearchResult.class
                );
            } catch (Exception error) {
                throw new AuraHandledException('AI 查询结果格式无效，请重新联网查询。');
            }
        }
        if (effectiveSelection == null) {
            effectiveSelection = new SccDeepSeekClient.ResearchResult();
            effectiveSelection.identityConfirmed = identityConfirmed;
            effectiveSelection.billingCountry = billingCountry;
            effectiveSelection.billingState = billingState;
            effectiveSelection.billingCity = billingCity;
            effectiveSelection.industry = industry;
            effectiveSelection.businessRegistrationNumber = businessRegistrationNumber;
            effectiveSelection.isMilitary = isMilitary;
            effectiveSelection.militaryIndustryCode = militaryIndustryCode;
            effectiveSelection.branchCode = branchCode;
        }
        if (String.isBlank(effectiveSelection.billingCountry)
            && String.isNotBlank(audit.AiResult__c)) {
            try {
                effectiveSelection = (SccDeepSeekClient.ResearchResult)JSON.deserialize(
                    audit.AiResult__c,
                    SccDeepSeekClient.ResearchResult.class
                );
            } catch (Exception error) {
                throw new AuraHandledException('无法读取 AI 审计结果，请重新联网查询。');
            }
        }
        Account value = load(accountId, true);
        enforceReplacement(value.xinyongdaima__c, replacementReason);
        applyOnlyMissing(value, effectiveSelection);

        SccRuleEngine.Context context = toContext(value, effectiveSelection);
        try {
            // Registry identity evidence comes from the persisted research, never editable browser input.
            SccDeepSeekClient.ResearchResult trustedResearch;
            if (String.isNotBlank(audit.AiResult__c)) {
                trustedResearch = (SccDeepSeekClient.ResearchResult)JSON.deserialize(
                    audit.AiResult__c, SccDeepSeekClient.ResearchResult.class);
            }
            String officialCode = matchedOfficialCode(value.Name, trustedResearch);
            SccGenerationService.Result generated;
            if (officialCode != null) {
                generated = new SccGenerationService.Result();
                generated.finalCode = officialCode;
                generated.codeBody = officialCode.substring(0, 17);
            } else {
                generated = SccGenerationService.generate(context, accountId);
            }
            value.xinyongdaima__c = generated.finalCode;
            Database.update(value, AccessLevel.SYSTEM_MODE);

            audit.Status__c = 'COMPLETED';
            audit.CodeBody__c = generated.codeBody;
            audit.FinalCode__c = generated.finalCode;
            audit.SequenceCategory__c = generated.sequenceCategory;
            audit.SequenceValue__c = generated.sequenceValue;
            audit.ReplacementReason__c = replacementReason;
            Database.update(audit, AccessLevel.SYSTEM_MODE);
            return generated.finalCode;
        } catch (Exception error) {
            throw new AuraHandledException(error.getMessage());
        }
    }

    @AuraEnabled
    public static String saveManual(Id accountId, String codeBody, String replacementReason) {
        requireGeneratePermission();
        Account value = load(accountId, true);
        enforceReplacement(value.xinyongdaima__c, replacementReason);
        SccManualCodeService.Preview preview = SccManualCodeService.preview(codeBody);
        value.xinyongdaima__c = preview.finalCode;
        Database.update(value, AccessLevel.SYSTEM_MODE);
        Database.insert(new CreditCodeGeneration__c(
            Account__c = accountId,
            Mode__c = 'MANUAL_CHECK_DIGIT',
            Status__c = 'COMPLETED',
            InputSnapshot__c = codeBody,
            CodeBody__c = preview.codeBody,
            FinalCode__c = preview.finalCode,
            ReplacementReason__c = replacementReason
        ), AccessLevel.SYSTEM_MODE);
        return preview.finalCode;
    }

    @TestVisible
    private static String matchedOfficialCode(String customerName, SccDeepSeekClient.ResearchResult research) {
        if (research == null || research.exactNameMatch != true
            || String.isBlank(customerName) || String.isBlank(research.matchedCompanyName)
            || !customerName.trim().equals(research.matchedCompanyName.trim())
            || String.isBlank(research.unifiedSocialCreditCode)
            || research.sources == null || research.sources.isEmpty()) return null;
        Boolean hasSource = false;
        for (SccDeepSeekClient.Source source : research.sources) {
            if (source != null && String.isNotBlank(source.url)
                && (source.url.startsWith('https://') || source.url.startsWith('http://'))) hasSource = true;
        }
        if (!hasSource) return null;
        String code = research.unifiedSocialCreditCode.trim().toUpperCase();
        String alphabet = '0123456789ABCDEFGHJKLMNPQRTUWXY';
        if (code.length() != 18) return null;
        Integer sum = 0;
        Integer weight = 1;
        for (Integer i = 0; i < 17; i++) {
            Integer digit = alphabet.indexOf(code.substring(i, i + 1));
            if (digit < 0) return null;
            sum += digit * weight;
            weight = Math.mod(weight * 3, 31);
        }
        Integer checkIndex = Math.mod(31 - Math.mod(sum, 31), 31);
        return code.endsWith(alphabet.substring(checkIndex, checkIndex + 1)) ? code : null;
    }

    @TestVisible
    private static void describeCodeDecision(String customerName, SccDeepSeekClient.ResearchResult research) {
        if (research == null) return;
        research.officialCodeAccepted = matchedOfficialCode(customerName, research) != null;
        if (research.officialCodeAccepted) {
            research.codeSource = '联网查询（已核验统一社会信用代码）';
            research.officialCodeRejectionReason = '';
            return;
        }
        research.codeSource = '内部编码规则';
        if (research.exactNameMatch != true || String.isBlank(research.matchedCompanyName)
            || String.isBlank(customerName) || customerName.trim() != research.matchedCompanyName.trim()) {
            research.officialCodeRejectionReason = '联网登记名称“' + research.matchedCompanyName
                + '”与客户名称“' + customerName + '”不完全一致，网上代码不采用，将按内部编码规则生成。';
        } else if (String.isBlank(research.unifiedSocialCreditCode)) {
            research.officialCodeRejectionReason = '未查询到可核验的18位统一社会信用代码，将按内部编码规则生成。';
        } else if (research.sources == null || research.sources.isEmpty()) {
            research.officialCodeRejectionReason = '联网代码缺少可核验的信息来源，不采用，将按内部编码规则生成。';
        } else {
            research.officialCodeRejectionReason = '联网代码未通过18位统一社会信用代码校验，不采用，将按内部编码规则生成。';
        }
    }

    @TestVisible
    private static void normalizeCertainMilitaryCodes(String customerName, SccDeepSeekClient.ResearchResult research) {
        if (research == null || String.isBlank(customerName)) return;
        String name = customerName.trim();
        if (name.contains('解放军') || name.contains('部队') || name.contains('空军')
            || name.contains('海军') || name.contains('陆军') || name.contains('火箭军')) {
            research.isMilitary = true;
        }
        if (research.isMilitary == true
            && (name.contains('医院') || name.contains('医疗') || name.contains('医学中心'))) {
            research.militaryIndustryCode = 'WH';
        }
        if (name.contains('空军')) research.branchCode = '03';
        else if (name.contains('海军')) research.branchCode = '02';
        else if (name.contains('火箭军')) research.branchCode = '05';
        else if (name.contains('陆军')) research.branchCode = '01';
    }

    private static Account load(Id accountId, Boolean lockRecord) {
        if (accountId == null) throw new AuraHandledException('缺少客户记录 ID。');
        String queryText = 'SELECT Id, Name, BillingCountry, BillingState, BillingCity, Industry, '
            + 'Business_Registration_Number__c, xinyongdaima__c FROM Account WHERE Id = :accountId LIMIT 1';
        if (lockRecord) queryText += ' FOR UPDATE';
        return (Account)Database.query(queryText)[0];
    }

    private static List<String> applyOnlyMissing(Account value, SccDeepSeekClient.ResearchResult selected) {
        List<String> filled = new List<String>();
        if (String.isBlank(value.BillingCountry) && String.isNotBlank(selected.billingCountry)) {
            value.BillingCountry = selected.billingCountry.trim(); filled.add('国家/地区');
        }
        if (String.isBlank(value.BillingState) && String.isNotBlank(selected.billingState)) {
            value.BillingState = selected.billingState.trim(); filled.add('省份');
        }
        if (String.isBlank(value.BillingCity) && String.isNotBlank(selected.billingCity)) {
            value.BillingCity = selected.billingCity.trim(); filled.add('城市');
        }
        if (String.isBlank(value.Industry) && String.isNotBlank(selected.industry)) {
            value.Industry = selected.industry.trim(); filled.add('行业');
        }
        if (String.isBlank(value.Business_Registration_Number__c)
            && String.isNotBlank(selected.businessRegistrationNumber)) {
            value.Business_Registration_Number__c = selected.businessRegistrationNumber.trim();
            filled.add('商业登记号码');
        }
        return filled;
    }

    private static List<String> findConflicts(Account value, SccDeepSeekClient.ResearchResult selected) {
        List<String> warnings = new List<String>();
        addConflict(warnings, '国家/地区', value.BillingCountry, selected.billingCountry);
        addConflict(warnings, '省份', value.BillingState, selected.billingState);
        addConflict(warnings, '城市', value.BillingCity, selected.billingCity);
        addConflict(warnings, '行业', value.Industry, selected.industry);
        addConflict(warnings, '商业登记号码', value.Business_Registration_Number__c, selected.businessRegistrationNumber);
        return warnings;
    }

    private static void addConflict(List<String> warnings, String label, String existingValue, String researchedValue) {
        if (String.isNotBlank(existingValue) && String.isNotBlank(researchedValue)
            && existingValue.trim().toUpperCase() != researchedValue.trim().toUpperCase()) {
            warnings.add(label + '：现有“' + existingValue + '”，联网结果“' + researchedValue + '”');
        }
    }

    private static SccRuleEngine.Context toContext(Account value, SccDeepSeekClient.ResearchResult selected) {
        SccRuleEngine.Context context = new SccRuleEngine.Context();
        context.name = value.Name;
        context.billingCountry = value.BillingCountry;
        context.billingState = value.BillingState;
        context.billingCity = value.BillingCity;
        context.industry = value.Industry;
        context.businessRegistrationNumber = value.Business_Registration_Number__c;
        context.aiMilitary = selected.isMilitary;
        context.aiMilitaryIndustryCode = selected.militaryIndustryCode;
        context.aiBranchCode = selected.branchCode;
        return context;
    }

    private static CreditCodeGeneration__c lockAudit(Id auditId, Id accountId) {
        if (auditId == null) throw new AuraHandledException('缺少 AI 查询审计记录。');
        List<SObject> rows = Database.queryWithBinds(
            'SELECT Id, Status__c, AiResult__c FROM CreditCodeGeneration__c '
                + 'WHERE Id = :auditId AND Account__c = :accountId AND Status__c = \'READY\' '
                + 'LIMIT 1 FOR UPDATE',
            new Map<String, Object>{'auditId' => auditId, 'accountId' => accountId},
            AccessLevel.SYSTEM_MODE
        );
        if (rows.isEmpty()) throw new AuraHandledException('AI 查询结果已失效，请重新查询。');
        return (CreditCodeGeneration__c)rows[0];
    }

    private static void enforceReplacement(String currentCode, String reason) {
        if (String.isBlank(currentCode)) return;
        if (!FeatureManagement.checkPermission('Scc_Replace_Existing_Code')) {
            throw new AuraHandledException('该客户已有编码，当前用户没有换码权限。');
        }
    }

    private static void requireGeneratePermission() {
        if (Test.isRunningTest() && bypassPermissionForTests) return;
        if (!FeatureManagement.checkPermission('Scc_Generate_Credit_Code')) {
            throw new AuraHandledException('当前用户没有客户编码生成权限。');
        }
    }

    private static String snapshot(Account value) {
        return JSON.serialize(new Map<String, Object>{
            'name' => value.Name, 'billingCountry' => value.BillingCountry,
            'billingState' => value.BillingState, 'billingCity' => value.BillingCity,
            'industry' => value.Industry,
            'businessRegistrationNumber' => value.Business_Registration_Number__c,
            'currentCode' => value.xinyongdaima__c
        });
    }

    private static String sourceUrls(List<SccDeepSeekClient.Source> sources) {
        List<String> values = new List<String>();
        if (sources != null) for (SccDeepSeekClient.Source source : sources) values.add(source.name + ': ' + source.url);
        return String.join(values, '\n');
    }

    private static String abbreviate(String value, Integer maxLength) {
        if (String.isBlank(value) || value.length() <= maxLength) return value;
        return value.left(maxLength);
    }

    public class AccountView {
        @AuraEnabled public String name;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String industry;
        @AuraEnabled public String businessRegistrationNumber;
        @AuraEnabled public String currentCode;
        @AuraEnabled public Boolean canReplace;
    }
}
