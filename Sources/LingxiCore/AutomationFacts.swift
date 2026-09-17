import Foundation

/// Explicit, versionable DTOs for facts already computed by the domain engines.
/// No reflection, private storage exposure, or language-model recalculation.
public enum AutomationFacts {
    public static func chart(_ value: FourPillarsChart) -> JSONValue {
        let details = NatalChartDetailsEngine().details(for: value)
        var pillars: [String: JSONValue] = ["year": .null, "month": .null, "day": .null, "hour": .null]
        for detail in details.pillars { pillars[detail.id] = pillarDetail(detail) }
        return .object([
            "instant": instant(value.instant), "instantUnixSeconds": .number(value.instant.timeIntervalSince1970),
            "timeZoneIdentifier": .string(value.timeZoneIdentifier),
            "dayBoundary": .string(value.dayBoundary.rawValue), "dayBoundaryLabel": .string(value.dayBoundary.label),
            "dayMaster": .string(details.dayMaster), "pillars": .object(pillars),
            "knownPillarCount": integer(details.pillars.count), "hasUnknownBirthHour": .bool(value.hour == nil),
            "instantRole": .string(value.hour == nil ? "candidateReference" : "resolvedInstant"),
            "previousJie": boundary(value.previousJie), "nextJie": boundary(value.nextJie),
            "calculationNote": .string(FourPillarsEngine.calculationNote),
            "lateZiNote": .string(FourPillarsEngine.lateZiNote),
            "detailScopeNote": .string(details.scopeNote),
            "sources": .array([
                source(title: FourPillarsEngine.algorithmSource, url: FourPillarsEngine.algorithmSourceURL),
                source(title: NatalChartDetailsEngine.sourceTitle, url: NatalChartDetailsEngine.sourceURL)
            ])
        ])
    }

    public static func luck(_ value: LuckCycleChart) -> JSONValue {
        .object([
            "birthChart": chart(value.birthChart), "birthInstant": instant(value.birthInstant),
            "timeZoneIdentifier": .string(value.timeZoneIdentifier),
            "gender": .string(value.gender.rawValue), "genderLabel": .string(value.gender.label),
            "direction": .string(value.direction.rawValue), "directionLabel": .string(value.direction.label),
            "startOffset": .object([
                "years": integer(value.startOffset.years), "months": integer(value.startOffset.months),
                "days": integer(value.startOffset.days), "hours": integer(value.startOffset.hours),
                "elapsedMinutes": integer(value.startOffset.elapsedMinutes)
            ]),
            "startAt": instant(value.startAt), "boundaryJie": boundary(value.boundaryJie),
            "cycles": .array(value.cycles.map { cycle in
                .object([
                    "id": integer(cycle.id), "index": integer(cycle.index), "pillar": pillar(cycle.pillar),
                    "start": instant(cycle.start), "end": instant(cycle.end),
                    "nominalStartAge": integer(cycle.nominalStartAge)
                ])
            }),
            "intervalConvention": .string("startInclusiveEndExclusive"),
            "methodNote": .string(value.methodNote), "boundaryNote": .string(LuckCycleEngine.boundaryNote),
            "source": source(title: LuckCycleEngine.sourceTitle, url: LuckCycleEngine.sourceURL)
        ])
    }

    public static func flowYear(_ value: LuckFlowYear, months: [LuckFlowMonth]) -> JSONValue {
        .object([
            "id": integer(value.id), "year": integer(value.year), "pillar": pillar(value.pillar),
            "start": instant(value.start), "end": instant(value.end),
            "months": .array(months.map { month in
                .object([
                    "id": integer(month.id), "index": integer(month.index), "label": .string(month.label),
                    "pillar": pillar(month.pillar), "start": instant(month.start), "end": instant(month.end),
                    "startJieName": .string(month.startJieName), "endJieName": .string(month.endJieName)
                ])
            }),
            "intervalConvention": .string("startInclusiveEndExclusive"),
            "flowMonthNote": .string(LuckCycleEngine.flowMonthNote),
            "source": source(title: LuckCycleEngine.sourceTitle, url: LuckCycleEngine.sourceURL)
        ])
    }

    public static func almanac(_ value: AlmanacDay) -> JSONValue {
        .object([
            "date": instant(value.date), "calendarDate": .string(civilDay(value.date)),
            "timeZoneIdentifier": .string(DayNote.calendarTimeZoneIdentifier),
            "dayGanZhi": .string(value.dayGanZhi), "yi": strings(value.yi), "ji": strings(value.ji),
            "auspiciousGods": strings(value.auspiciousGods), "inauspiciousGods": strings(value.inauspiciousGods),
            "dutyGod": .string(value.dutyGod), "dutyGodType": .string(value.dutyGodType),
            "luck": .string(value.luck), "clash": .string(value.clash), "sha": .string(value.sha),
            "positions": .array(value.positions.map(position)), "pengZu": strings(value.pengZu),
            "mansion": .string(value.mansion), "mansionLuck": .string(value.mansionLuck),
            "officer": .string(value.officer), "liuYao": .string(value.liuYao),
            "wuHou": .string(value.wuHou), "hou": .string(value.hou), "dayLu": .string(value.dayLu),
            "fetalPosition": .string(value.fetalPosition), "monthFetalPosition": .string(value.monthFetalPosition),
            "moonPhase": .string(value.moonPhase), "yearNineStar": nineStar(value.yearNineStar),
            "monthNineStar": nineStar(value.monthNineStar), "dayNineStar": nineStar(value.dayNineStar),
            "hours": .array(value.hours.map(hour)), "sourceLabel": .string(value.sourceLabel),
            "sourceURL": .string(value.sourceURL), "boundaryNote": .string(value.boundaryNote),
            "classification": .string("traditionalRules")
        ])
    }

    public static func reading(_ value: PersonalDailyReadingReport) -> JSONValue {
        .object([
            "dayMaster": .string(value.dayMaster), "headline": .string(value.headline), "summary": .string(value.summary),
            "strength": .string(value.strength.rawValue), "strengthContext": .string(value.strengthContext),
            "natalMonth": monthContext(value.natalMonth), "flowMonth": monthContext(value.flowMonth),
            "observations": .array(value.observations.map { item in
                .object([
                    "id": .string(item.id), "title": .string(item.title), "body": .string(item.body),
                    "evidence": strings(item.evidence), "ruleNote": .string(item.ruleNote),
                    "sourceTitle": .string(item.sourceTitle), "sourceURL": .string(item.sourceURL)
                ])
            }),
            "rootEvidence": .array(value.rootEvidence.map { item in
                .object([
                    "id": .string(item.id), "pillarID": .string(item.pillarID), "pillarLabel": .string(item.pillarLabel),
                    "pillar": pillar(item.pillar), "hiddenStem": .string(item.hiddenStem),
                    "isMainQi": .bool(item.isMainQi), "description": .string(item.description)
                ])
            }),
            "periods": .array(value.periods.map { item in
                .object([
                    "id": .string(item.id), "period": .string(item.period.rawValue),
                    "periodLabel": .string(item.period.label), "perspective": .string(item.period.perspective),
                    "pillar": pillar(item.pillar), "tenGod": tenGod(item.tenGod), "title": .string(item.title),
                    "theme": .string(item.theme), "explanation": .string(item.explanation),
                    "conditionalInterpretation": .string(item.conditionalInterpretation), "action": .string(item.action),
                    "ruleNote": .string(item.ruleNote), "sourceTitle": .string(item.sourceTitle), "sourceURL": .string(item.sourceURL)
                ])
            }),
            "relationships": relationships(value.relationships), "actions": strings(value.actions),
            "hasUnknownBirthHour": .bool(value.hasUnknownBirthHour), "scopeNote": .string(value.scopeNote)
        ])
    }

    private static func pillar(_ value: Ganzhi) -> JSONValue {
        .object([
            "index": integer(value.index), "text": .string(value.text), "stem": .string(value.stem),
            "branch": .string(value.branch), "stemIndex": integer(value.stemIndex), "branchIndex": integer(value.branchIndex)
        ])
    }

    private static func pillarDetail(_ value: NatalPillarDetail) -> JSONValue {
        .object([
            "id": .string(value.id), "label": .string(value.label), "pillar": pillar(value.pillar),
            "stemElement": .string(value.stemElement), "branchElement": .string(value.branchElement),
            "tenGod": .string(value.tenGod), "hiddenStems": .array(value.hiddenStems.map { item in
                .object([
                    "stemIndex": integer(item.stemIndex), "stem": .string(item.stem),
                    "element": .string(item.element), "tenGod": .string(item.tenGod)
                ])
            }),
            "naYin": .string(value.naYin), "dayMasterStage": .string(value.dayMasterStage),
            "selfStage": .string(value.selfStage), "xun": .string(value.xun), "xunKong": .string(value.xunKong)
        ])
    }

    private static func boundary(_ value: SolarTermBoundary) -> JSONValue {
        .object([
            "index": integer(value.index), "name": .string(value.name), "isJie": .bool(value.isJie),
            "date": instant(value.date), "unixSeconds": .number(value.date.timeIntervalSince1970)
        ])
    }

    private static func hour(_ value: AlmanacHour) -> JSONValue {
        .object([
            "id": integer(value.id), "label": .string(value.label), "startMinute": integer(value.startMinute),
            "endMinute": integer(value.endMinute), "timeRange": .string(value.timeRange), "ganZhi": .string(value.ganZhi),
            "yi": strings(value.yi), "ji": strings(value.ji), "dutyGod": .string(value.dutyGod),
            "dutyGodType": .string(value.dutyGodType), "luck": .string(value.luck), "clash": .string(value.clash),
            "sha": .string(value.sha), "positions": .array(value.positions.map(position)), "nineStar": nineStar(value.nineStar)
        ])
    }

    private static func position(_ value: AlmanacPosition) -> JSONValue {
        .object(["label": .string(value.label), "raw": .string(value.raw), "direction": .string(value.direction)])
    }

    private static func nineStar(_ value: AlmanacNineStar) -> JSONValue {
        .object([
            "number": .string(value.number), "color": .string(value.color), "element": .string(value.element),
            "name": .string(value.name), "display": .string(value.display), "palaces": .array(value.palaces.map { item in
                .object([
                    "palace": .string(item.palace), "direction": .string(item.direction), "number": .string(item.number),
                    "element": .string(item.element), "starName": .string(item.starName)
                ])
            })
        ])
    }

    private static func monthContext(_ value: BaziMonthContext) -> JSONValue {
        .object([
            "title": .string(value.title), "pillar": pillar(value.pillar), "mainStem": .string(value.mainStem),
            "element": .string(value.element), "tenGod": tenGod(value.tenGod), "relationship": .string(value.relationship),
            "summary": .string(value.summary), "ruleNote": .string(value.ruleNote),
            "sourceTitle": .string(value.sourceTitle), "sourceURL": .string(value.sourceURL)
        ])
    }

    private static func tenGod(_ value: BaziTenGodReading) -> JSONValue {
        .object([
            "kind": .string(value.kind.rawValue), "label": .string(value.label), "explanation": .string(value.explanation),
            "reflection": .string(value.reflection), "sourceTitle": .string(value.sourceTitle), "sourceURL": .string(value.sourceURL)
        ])
    }

    private static func relationInput(_ value: BaziRelationInput) -> JSONValue {
        .object([
            "label": .string(value.label), "stemIndex": integer(value.stemIndex),
            "branchIndex": integer(value.branchIndex), "ganZhi": .string(value.ganZhi)
        ])
    }

    private static func relationships(_ value: BaziRelationshipReport) -> JSONValue {
        .object([
            "flowDay": relationInput(value.flowDay), "dayMasterName": .string(value.dayMasterName),
            "tenGod": tenGod(value.tenGod), "tendency": .string(value.tendency.rawValue),
            "tendencyLabel": .string(value.tendency.label), "checkedPillarCount": integer(value.checkedPillarCount),
            "summary": .string(value.summary), "reflection": .string(value.reflection), "scopeNote": .string(value.scopeNote),
            "relations": .array(value.relations.map { item in
                .object([
                    "id": .string(item.id), "kind": .string(item.kind.rawValue), "kindLabel": .string(item.kind.label),
                    "flowDay": relationInput(item.flowDay), "pillar": relationInput(item.pillar),
                    "pillarIndex": integer(item.pillarIndex), "pairName": .string(item.pairName), "title": .string(item.title),
                    "explanation": .string(item.explanation), "reflection": .string(item.reflection),
                    "sourceTitle": .string(item.sourceTitle), "sourceURL": .string(item.sourceURL)
                ])
            })
        ])
    }

    private static func source(title: String, url: String) -> JSONValue {
        .object(["title": .string(title), "url": .string(url)])
    }
    private static func strings(_ values: [String]) -> JSONValue { .array(values.map(JSONValue.string)) }
    private static func integer(_ value: Int) -> JSONValue { .number(Double(value)) }
    private static func instant(_ value: Date) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .string(formatter.string(from: value))
    }
    private static func civilDay(_ value: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: DayNote.calendarTimeZoneIdentifier)!
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
