public class SccConstants {
    public static final String CATEGORY_SPECIAL_UNIT = 'SPECIAL_UNIT';
    public static final String CATEGORY_MILITARY = 'MILITARY';
    public static final String CATEGORY_HONG_KONG = 'HONG_KONG';
    public static final String CATEGORY_MACAU = 'MACAU';
    public static final String CATEGORY_TAIWAN = 'TAIWAN';
    public static final String CATEGORY_FOREIGN = 'FOREIGN';

    public static final Set<String> SEQUENCE_CATEGORIES = new Set<String>{
        CATEGORY_SPECIAL_UNIT,
        CATEGORY_MILITARY,
        CATEGORY_HONG_KONG,
        CATEGORY_MACAU,
        CATEGORY_TAIWAN,
        CATEGORY_FOREIGN
    };

    private SccConstants() {}
}