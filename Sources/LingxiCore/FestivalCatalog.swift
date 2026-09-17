import Foundation

/// A sourced cultural observance, not a statutory public-holiday or prediction record.
public struct Festival: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let lunarMonth: Int
    public let lunarDay: Int
    public let summary: String
    public let region: String
    public let sourceTitle: String
    public let sourceURL: String

    public init(id: String, name: String, kind: String, lunarMonth: Int, lunarDay: Int,
                summary: String, region: String, sourceTitle: String, sourceURL: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.lunarMonth = lunarMonth
        self.lunarDay = lunarDay
        self.summary = summary
        self.region = region
        self.sourceTitle = sourceTitle
        self.sourceURL = sourceURL
    }
}

public enum FestivalCatalog {
    private static let festivalSource = "https://tv.cctv.cn/special/zgctjr/festivalchina/index.shtml"
    private static let templeSource = "https://www.ctc.org.hk/zh-hans/festival/"

    public static let all: [Festival] = [
        holiday("spring-festival", "春节", 1, 1, "农历新年的开始，以庆贺新岁寄托祝愿。"),
        holiday("lantern-festival", "元宵节", 1, 15, "又称上元节、灯节，是新年第一个月圆节日。"),
        holiday("dragon-boat", "端午节", 5, 5, "又称端阳节、龙舟节，各地保留不同的节俗。"),
        holiday("qixi", "七夕", 7, 7, "源于乞巧传统，也寄托人们对美好关系的愿望。"),
        holiday("mid-autumn", "中秋节", 8, 15, "以月圆寄托团圆与思念，习俗随地域而异。"),
        holiday("double-ninth", "重阳节", 9, 9, "包含敬老与纪念先人的传统。"),
        deity("jade-emperor", "玉皇大帝诞", 1, 9, "香港部分庙宇于此日庆贺玉皇大帝诞辰。"),
        deity("man-cheung", "文昌诞", 2, 3, "香港部分庙宇的文昌节诞日。"),
        deity("guanyin-birthday", "观音诞", 2, 19, "此条记观音降生纪念日；另有成道等纪念日。"),
        deity("pak-tai", "北帝诞", 3, 3, "香港北帝信俗的诞期；当地庆典安排可能调整。"),
        Festival(
            id: "tin-hau", name: "天后诞", kind: "神诞", lunarMonth: 3, lunarDay: 23,
            summary: "又称妈祖诞。香港社区以巡游、神功戏等庆贺，也可能另择活动日。",
            region: "香港天后信俗；其他地区另有传承", sourceTitle: "香港非物质文化遗产办事处 · 香港天后诞",
            sourceURL: "https://www.icho.hk/tc/web/icho/representative_list_tin_hau.html"
        ),
        deity("guanyin-enlightenment", "观音成道日", 6, 19, "香港观音信俗的成道纪念日，与二月降生纪念日不同。"),
        Festival(
            id: "dragon-head", name: "龙抬头", kind: "节日", lunarMonth: 2, lunarDay: 2,
            summary: "二月二与迎春、春耕的民俗相连，不同地区有各自的饮食与迎春习惯。",
            region: "中国二月二民俗；各地习惯不同", sourceTitle: "中国非物质文化遗产网 · 二月二 龙抬头",
            sourceURL: "https://www.ihchina.cn/news_1_details/10632.html"
        ),
        Festival(
            id: "zhongyuan", name: "中元节", kind: "节日", lunarMonth: 7, lunarDay: 15,
            summary: "以追念先人、表达感恩为主题。此条采用七月十五，部分地方与庙宇另择日期。",
            region: "采用湖北天门所记七月十五；地域日期有别", sourceTitle: "天门市人民政府 · 中元节习俗",
            sourceURL: "https://www.tianmen.gov.cn/zjtm/tmwh/tmms/201604/t20160419_1930964.shtml"
        ),
        Festival(
            id: "laba", name: "腊八节", kind: "节日", lunarMonth: 12, lunarDay: 8,
            summary: "以煮粥、分享食物迎接岁末。杭州腊八节习俗保留了寺院与社区施粥的传统。",
            region: "杭州腊八习俗；中国各地另有传承", sourceTitle: "中国非物质文化遗产网 · 腊八节习俗",
            sourceURL: "https://www.ihchina.cn/art/detail/id/23622.html"
        ),
        deity("che-kung-new-year", "车公诞", 1, 2, "此条记沙田车公庙正月诞期；同一传统另有三月、六月及八月诞期。"),
        deity("earth-god-spring", "土地诞", 2, 2, "此条记筲箕湾城隍庙二月诞期，该庙另列五月初十。"),
        deity("hung-shing", "洪圣诞", 2, 13, "鸭脷洲与长洲部分庙宇于二月十三纪念洪圣。"),
        deity("tam-kung", "谭公诞", 4, 8, "香港谭公信俗的诞期；本条采用庙宇委员会所列农历日期。"),
        deity("kwan-ti", "武帝诞（关帝诞）", 6, 24, "深水埗关帝庙于六月廿四贺诞，以关帝信俗为背景。"),
        deity("guanyin-autumn", "观音诞（飞升纪念）", 9, 19, "此条保留香港庙宇表的飞升纪念名称；其他佛教传统称观音出家日。"),
        buddhist("manjushri", "文殊菩萨诞", 4, 4, "香港佛教联合会年历列四月初四为文殊菩萨纪念日。"),
        buddhist("buddha-birthday", "佛诞（浴佛节）", 4, 8, "汉传佛教常于此日纪念释迦牟尼佛诞生，并举行浴佛等活动。"),
        buddhist("amitabha", "阿弥陀佛诞", 11, 17, "香港佛教联合会年历所列的阿弥陀佛纪念日。")
    ]

    private static func holiday(_ id: String, _ name: String, _ month: Int, _ day: Int, _ summary: String) -> Festival {
        Festival(id: id, name: name, kind: "节日", lunarMonth: month, lunarDay: day,
                 summary: summary, region: "中国传统节日；具体习俗因地域而异",
                 sourceTitle: "央视网 · 过节啦·中国传统节日", sourceURL: festivalSource)
    }

    private static func deity(_ id: String, _ name: String, _ month: Int, _ day: Int, _ summary: String) -> Festival {
        Festival(id: id, name: name, kind: "神诞", lunarMonth: month, lunarDay: day,
                 summary: summary, region: "香港华人庙宇委员会所列庙宇传统",
                 sourceTitle: "华人庙宇委员会 · 节诞日期", sourceURL: templeSource)
    }

    private static func buddhist(_ id: String, _ name: String, _ month: Int, _ day: Int, _ summary: String) -> Festival {
        Festival(id: id, name: name, kind: "神诞", lunarMonth: month, lunarDay: day,
                 summary: summary, region: "香港佛教联合会所列汉传佛教纪念日",
                 sourceTitle: "香港佛教联合会 · 2025 年历（佛菩萨纪念日期表）",
                 sourceURL: "https://www.hkbuddhist.org/editor_upload_image/file/calendar2025.pdf")
    }

}
