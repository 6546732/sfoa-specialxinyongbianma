@IsTest
private class SccDeepSeekClientTest {
    @IsTest
    static void buildsChineseTraditionalAndJapaneseSearchNames() {
        List<String> values = SccDeepSeekClient.searchNameVariants('关东电化工业株式会社');
        System.assert(values.contains('关东电化工业株式会社'));
        System.assert(values.contains('關東電化工業株式会社'));
        System.assert(values.contains('関東電化工業株式会社'));

        values = SccDeepSeekClient.searchNameVariants('中国人民解放军空军总医院');
        System.assert(values.contains('中国人民解放军空军特色医学中心'));
        System.assert(values.contains('空军特色医学中心'));
    }
    @IsTest
    static void parsesStructuredResponseAndValidatesCodes() {
        String payload = JSON.serialize(new Map<String,Object>{
            'output_text' => JSON.serialize(new Map<String,Object>{
                'identityConfirmed'=>true, 'billingCountry'=>'香港',
                'isMilitary'=>true, 'militaryIndustryCode'=>'INVALID', 'branchCode'=>'99',
                'sources'=>new List<Object>{new Map<String,Object>{'name'=>'登记处','url'=>'https://example.test/company'}}
            })
        });
        SccDeepSeekClient.ResearchResult result = SccDeepSeekClient.parseResponse(payload);
        System.assert(result.identityConfirmed);
        System.assertEquals('', result.militaryIndustryCode);
        System.assertEquals('', result.branchCode);
        System.assertEquals(1, result.sources.size());
    }

    @IsTest
    static void parsesAndLimitsHongKongMacauTaiwanMatches() {
        List<Object> matches = new List<Object>();
        for (Integer i = 0; i < 4; i++) {
            matches.add(new Map<String,Object>{
                'companyName'=>'相似客户' + i,
                'territory'=>i == 1 ? '澳门' : i == 2 ? '台湾' : '香港',
                'similarityReason'=>'名称核心词和行业相同',
                'matchedFactors'=>new List<String>{'名称核心词','行业'},
                'confidence'=>88,
                'sources'=>new List<Object>{new Map<String,Object>{
                    'name'=>'登记来源','url'=>'https://example.test/similar/' + i
                }}
            });
        }
        String payload = JSON.serialize(new Map<String,Object>{
            'output_text'=>JSON.serialize(new Map<String,Object>{
                'sources'=>new List<Object>(), 'similarCustomers'=>matches
            })
        });
        SccDeepSeekClient.ResearchResult result = SccDeepSeekClient.parseResponse(payload);
        System.assertEquals(3, result.similarCustomers.size());
        System.assertEquals('名称核心词和行业相同', result.similarCustomers[0].similarityReason);
    }

    @IsTest
    static void rejectsIncompleteSimilarCustomer() {
        assertInvalid(JSON.serialize(new Map<String,Object>{
            'output_text'=>JSON.serialize(new Map<String,Object>{
                'sources'=>new List<Object>(),
                'similarCustomers'=>new List<Object>{new Map<String,Object>{
                    'companyName'=>'错误客户','territory'=>'大陆','similarityReason'=>''
                }}
            })
        }));
    }

    @IsTest
    static void rejectsInvalidSourceUrlAndInvalidJson() {
        assertInvalid(JSON.serialize(new Map<String,Object>{'output_text'=>'not json'}));
        assertInvalid(JSON.serialize(new Map<String,Object>{
            'output_text'=>JSON.serialize(new Map<String,Object>{
                'sources'=>new List<Object>{new Map<String,Object>{'name'=>'坏来源','url'=>'javascript:test'}}
            })
        }));
    }

    @IsTest
    static void acceptsJsonSurroundedByModelText() {
        String body = JSON.serialize(new Map<String,Object>{
            'output_text'=>'查询结果如下：\n```json\n{"identityConfirmed":true,"sources":[]}\n```\n已完成。'
        });
        System.assert(SccDeepSeekClient.parseResponse(body).identityConfirmed);
    }

    @IsTest
    static void toleratesSimilarCustomerFieldTypes() {
        String body = JSON.serialize(new Map<String,Object>{
            'output_text'=>JSON.serialize(new Map<String,Object>{
                'similarCustomers'=>new List<Object>{new Map<String,Object>{
                    'companyName'=>'中国生物制药有限公司','territory'=>'香港特别行政区',
                    'similarityReason'=>'同为香港上市制药集团','confidence'=>'88%'
                }}
            })
        });
        List<SccDeepSeekClient.SimilarCustomer> values = SccDeepSeekClient.parseSimilarResponse(body);
        System.assertEquals(1, values.size());
        System.assertEquals('香港', values[0].territory);
        System.assertEquals(88, values[0].confidence);
    }

    private static void assertInvalid(String body) {
        Boolean thrown=false;
        try { SccDeepSeekClient.parseResponse(body); }
        catch (SccDeepSeekClient.DeepSeekException expected) { thrown=true; }
        System.assert(thrown);
    }
}
