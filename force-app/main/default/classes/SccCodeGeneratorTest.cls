@IsTest
private class SccCodeGeneratorTest {
    @IsTest
    static void validatesCompleteCodes() {
        String complete = SccCodeGenerator.appendCheckCharacter('91320412313744932');
        System.assert(SccCodeGenerator.isValidCompleteCode(complete));
        System.assert(SccCodeGenerator.isValidCompleteCode(' ' + complete.toLowerCase() + ' '));
        System.assertEquals(false, SccCodeGenerator.isValidCompleteCode(complete.left(17) + '0'));
        System.assertEquals(false, SccCodeGenerator.isValidCompleteCode(''));
        System.assertEquals(false, SccCodeGenerator.isValidCompleteCode('INVALID'));
        SccManualCodeService.Preview preview = SccManualCodeService.preview(complete);
        System.assertEquals(complete, preview.finalCode);
        System.assert(preview.inputWasCompleteCode);
        Boolean rejected = false;
        try { SccManualCodeService.preview(complete.left(17) + '0'); }
        catch (SccCodeGenerator.InvalidCodeBodyException expected) { rejected = true; }
        System.assert(rejected);
    }
    @IsTest
    static void calculatesConfirmedCompatibilityVectors() {
        Map<String, String> expectedByBody = new Map<String, String>{
            'SHK77254080' => 'A',
            'SHK0690133' => '4',
            'SHK62935578' => '4',
            'SHK30653538' => '9',
            'SHK06886002' => '7',
            'SHK69721516' => 'E',
            'SHK0039' => 'F',
            'SMC0026' => 'N',
            'SJP0086' => '6',
            'SSG0087' => 'D'
        };

        for (String body : expectedByBody.keySet()) {
            System.assertEquals(
                expectedByBody.get(body),
                SccCodeGenerator.calculateCheckCharacter(body),
                '兼容性向量计算不一致：' + body
            );
        }
    }

    @IsTest
    static void normalizesManualInputAndPreservesLeadingZeroes() {
        SccManualCodeService.Preview result = SccManualCodeService.preview('  shk0690133  ');

        System.assertEquals('SHK0690133', result.codeBody);
        System.assertEquals('4', result.checkCharacter);
        System.assertEquals('SHK06901334', result.finalCode);
    }

    @IsTest
    static void rejectsBlankAndPunctuation() {
        assertInvalid(null);
        assertInvalid('  ');
        assertInvalid('SHK-0690133');
        assertInvalid('SHK 0690133');
    }

    private static void assertInvalid(String value) {
        Boolean rejected = false;
        try {
            SccCodeGenerator.appendCheckCharacter(value);
        } catch (SccCodeGenerator.InvalidCodeBodyException error) {
            rejected = true;
        }
        System.assert(rejected, '应拒绝非法编码主体：' + value);
    }
}
