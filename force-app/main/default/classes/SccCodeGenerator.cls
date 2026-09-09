public with sharing class SccCodeGenerator {
    @TestVisible
    private static final String OUTPUT_CHARACTERS = '0123456789ABCDEFGHJKLMNPQRTUWXY';
    private static final String INPUT_DIGITS = '0123456789';
    private static final String INPUT_LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    private static final Integer MODULUS = 31;
    private static final Integer MAX_BODY_LENGTH = 254;

    public static String normalizeBody(String rawBody) {
        if (String.isBlank(rawBody)) {
            throw new InvalidCodeBodyException('编码主体不能为空。');
        }

        String normalized = rawBody.trim().toUpperCase();
        if (normalized.length() > MAX_BODY_LENGTH) {
            throw new InvalidCodeBodyException('编码主体不能超过 254 位。');
        }
        if (!Pattern.matches('^[0-9A-Z]+$', normalized)) {
            throw new InvalidCodeBodyException('编码主体只能包含数字和大写英文字母。');
        }
        return normalized;
    }

    public static String appendCheckCharacter(String rawBody) {
        String normalized = normalizeBody(rawBody);
        return normalized + calculateNormalizedBodyCheckCharacter(normalized);
    }

    public static String calculateCheckCharacter(String rawBody) {
        return calculateNormalizedBodyCheckCharacter(normalizeBody(rawBody));
    }

    public static Boolean isValidCompleteCode(String rawCode) {
        if (String.isBlank(rawCode)) return false;
        String normalized = rawCode.trim().toUpperCase();
        if (normalized.length() != 18 || !Pattern.matches('^[0-9A-Z]{18}$', normalized)) return false;
        String body = normalized.substring(0, 17);
        try {
            return normalized.endsWith(calculateNormalizedBodyCheckCharacter(body));
        } catch (InvalidCodeBodyException error) {
            return false;
        }
    }

    private static String calculateNormalizedBodyCheckCharacter(String normalizedBody) {
        Integer total = 0;
        Integer powerOfThree = 1;

        for (Integer index = 0; index < normalizedBody.length(); index++) {
            Integer characterValue = inputValue(normalizedBody.mid(index, 1));
            total = Math.mod(total + Math.mod(characterValue * powerOfThree, MODULUS), MODULUS);
            powerOfThree = Math.mod(powerOfThree * 3, MODULUS);
        }

        Integer checkIndex = Math.mod(MODULUS - total, MODULUS);
        return OUTPUT_CHARACTERS.mid(checkIndex, 1);
    }

    private static Integer inputValue(String characterValue) {
        Integer digitIndex = INPUT_DIGITS.indexOf(characterValue);
        if (digitIndex >= 0) return digitIndex;

        Integer letterIndex = INPUT_LETTERS.indexOf(characterValue);
        if (letterIndex >= 0) return 10 + letterIndex;

        throw new InvalidCodeBodyException('编码主体包含不支持的字符：' + characterValue);
    }

    public class InvalidCodeBodyException extends Exception {}
}
