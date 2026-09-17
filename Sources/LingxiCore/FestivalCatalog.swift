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
        deity("guanyin-enlightenment", "观音成道日", 6, 19, "香港观音信俗的成道纪念日，与二月降生纪念日不同。")
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
}
