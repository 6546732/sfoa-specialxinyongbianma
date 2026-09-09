public with sharing class SccManualCodeService {
    @AuraEnabled(cacheable=true)
    public static Preview preview(String codeBody) {
        String normalizedInput = String.isBlank(codeBody) ? codeBody : codeBody.trim().toUpperCase();
        Boolean suppliedCompleteCode = normalizedInput != null && normalizedInput.length() == 18;
        String normalizedBody;
        if (suppliedCompleteCode) {
            if (!SccCodeGenerator.isValidCompleteCode(normalizedInput)) {
                throw new SccCodeGenerator.InvalidCodeBodyException('完整的18位编码校验位不正确。');
            }
            normalizedBody = normalizedInput.substring(0, 17);
        } else {
            normalizedBody = SccCodeGenerator.normalizeBody(normalizedInput);
        }
        Preview result = new Preview();
        result.codeBody = normalizedBody;
        result.checkCharacter = SccCodeGenerator.calculateCheckCharacter(normalizedBody);
        result.finalCode = normalizedBody + result.checkCharacter;
        result.inputWasCompleteCode = suppliedCompleteCode;
        return result;
    }

    public class Preview {
        @AuraEnabled public String codeBody { get; set; }
        @AuraEnabled public String checkCharacter { get; set; }
        @AuraEnabled public String finalCode { get; set; }
        @AuraEnabled public Boolean inputWasCompleteCode { get; set; }
    }
}
