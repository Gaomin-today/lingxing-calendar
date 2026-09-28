import SwiftUI
import LingxiCore

struct AppearanceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceStore.shared
    @State private var elementFeedback: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("外观与灵宠").font(.system(size: 23, weight: .medium, design: .serif))
                    Text("选一位陪伴，也选一种今天喜欢的颜色。").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(JadeButton())
            }.padding(22)
            Divider().overlay(Theme.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    livePreview
                    spiritSelection
                    colorSelection
                    HStack(alignment: .top) {
                        Text("五行标签用于外观分类，可按自己的喜好或已有解读来选；它们不会改变排盘结果，也不代表已确定喜用神。").font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 22)
                        Button("恢复默认") { appearance.reset(); elementFeedback = nil }.buttonStyle(QuietButton())
                    }
                }.padding(22)
            }
        }
        .frame(width: 800, height: 780)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper)
        .tint(Theme.jade)
    }

    private var livePreview: some View {
        HStack(spacing: 0) {
            VStack(spacing: 10) {
                SpiritView(size: 90)
                Text(appearance.preferences.spirit.name).font(.system(size: 16, weight: .medium, design: .serif))
                Text("你的桌面陪伴").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.frame(width: 158).padding(.vertical, 18).background(Theme.panel)
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("一眼看见，自己的今天").font(.system(size: 18, weight: .medium, design: .serif)); Spacer(); Pill(text: "实时预览", color: Theme.accent) }
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.jade).frame(width: 40, height: 44).overlay(Text("今").foregroundStyle(.white).font(.system(size: 16)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("主色 · 侧栏、选中日期、按钮").font(.system(size: 12)).foregroundStyle(Theme.jade)
                        Text(appearance.preferences.secondary == nil ? "单色 · 卡片沿用同一色系" : "辅色 · 卡片、卦象与内容点缀").font(.system(size: 11)).foregroundStyle(Theme.accent)
                    }
                }
                Text(appearance.preferences.spirit.detail).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.softAccent, in: RoundedRectangle(cornerRadius: 8))
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
    }

    private var spiritSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选一位灵宠").font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                Text("当前：" + appearance.preferences.spirit.name).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 8) {
                filterButton("全部", selected: appearance.preferences.preferredElements.isEmpty) {
                    appearance.update { $0.clearElements() }; elementFeedback = nil
                }
                ForEach(AppearanceElement.allCases) { element in
                    filterButton(element.label, selected: appearance.preferences.preferredElements.contains(element)) {
                        appearance.update { preferences in
                            let changed = preferences.toggleElement(element)
                            elementFeedback = changed ? nil : "最多选两项偏好；先取消一项，再选择新的。"
                        }
                    }
                }
                Spacer()
                Text("偏好筛选 · 最多两项").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            if let elementFeedback { Text(elementFeedback).font(.system(size: 11)).foregroundStyle(Theme.secondary) }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(appearance.preferences.matchingSpirits) { spirit in
                    Button { appearance.update { $0.spirit = spirit } } label: {
                        VStack(spacing: 5) {
                            HStack { Spacer(); if appearance.preferences.spirit == spirit { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.jade) } else { Image(systemName: "circle").foregroundStyle(Theme.line) } }.font(.system(size: 14))
                            SpiritPortrait(spirit: spirit, size: 92, primary: appearance.primaryColor, accent: appearance.accentColor)
                            HStack(spacing: 6) {
                                Text(spirit.name).font(.system(size: 14, weight: .medium, design: .serif))
                                Text(spirit.elements.map(\.label).joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(Theme.secondary)
                            }
                            Text(spirit.detail).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        .padding(12).frame(maxWidth: .infinity).background(appearance.preferences.spirit == spirit ? Theme.softJade.opacity(0.7) : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(appearance.preferences.spirit == spirit ? Theme.jade : Theme.line, lineWidth: appearance.preferences.spirit == spirit ? 1.5 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("选择灵宠" + spirit.name)
                }
            }
            Text("双子以成对月牙筊杯为造型。筛选只改变候选列表，不会替你切换已经选好的灵宠。").font(.system(size: 10)).foregroundStyle(Theme.secondary)
        }
    }

    private var colorSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("配一套颜色").font(.system(size: 17, weight: .medium, design: .serif))
                Spacer()
                Picker("配色方式", selection: Binding(get: { appearance.preferences.secondary != nil }, set: { enabled in
                    appearance.update { $0.secondary = enabled ? AppearanceElement.earth.color : nil }
                })) { Text("单色").tag(false); Text("双色").tag(true) }.pickerStyle(.segmented).frame(width: 175).labelsHidden()
            }
            Text("先选五行预设，也可以用取色器或十六进制色值自定义。配色与灵宠可以独立选择。").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            AppearanceColorEditor(title: "主色", detail: "侧栏、按钮、选中日期", value: Binding(get: { appearance.preferences.primary }, set: { value in appearance.update { $0.primary = value } }))
            if appearance.preferences.secondary != nil {
                AppearanceColorEditor(title: "辅色", detail: "卡片底色、卦象与内容点缀", value: Binding(get: { appearance.preferences.secondary ?? appearance.preferences.primary }, set: { value in appearance.update { $0.secondary = value } }))
            }
            Text("为保证文字清晰，过浅的颜色会在按钮和文字上自动加深；纸色与提示色保持稳定。设置会立即保存，并同步到桌面灵宠。").font(.system(size: 10)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 13).padding(.vertical, 7).background(selected ? Theme.jade : Theme.card, in: Capsule()).foregroundStyle(selected ? .white : Theme.secondary).overlay(Capsule().stroke(selected ? Theme.jade : Theme.line, lineWidth: 1)) }.buttonStyle(.plain)
    }
}

private struct AppearanceColorEditor: View {
    let title: String
    let detail: String
    @Binding var value: AppearanceColor
    @State private var hex: String
    init(title: String, detail: String, value: Binding<AppearanceColor>) {
        self.title = title; self.detail = detail; self._value = value
        self._hex = State(initialValue: value.wrappedValue.hexString)
    }
    private var parsed: AppearanceColor? { AppearanceColor(hexString: hex) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill(Color(appearance: value)).frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Spacer()
                ColorPicker(title + "自定义颜色", selection: Binding(get: { Color(appearance: value) }, set: { color in if let result = color.appearanceColor { value = result } }), supportsOpacity: false).labelsHidden().accessibilityLabel(title + "自定义颜色")
                TextField("#3F6856", text: $hex).font(.system(size: 11, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 95).onSubmit(applyHex).accessibilityLabel(title + "十六进制色值")
                Button("应用") { applyHex() }.font(.system(size: 11)).buttonStyle(QuietButton()).disabled(parsed == nil || parsed == value)
            }
            HStack(spacing: 9) {
                ForEach(AppearanceElement.allCases) { element in
                    Button { value = element.color } label: {
                        HStack(spacing: 5) { Circle().fill(Color(appearance: element.color)).frame(width: 13, height: 13); Text(element.label + " · " + element.colorName).font(.system(size: 10)) }
                            .padding(.horizontal, 9).padding(.vertical, 7).background(value == element.color ? Theme.softJade : Theme.paper, in: Capsule()).overlay(Capsule().stroke(value == element.color ? Theme.jade : Theme.line, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(title + "选择" + element.label + element.colorName)
                }
                Spacer(minLength: 0)
            }
            if parsed == nil { Text("请输入六位色值，例如 #3F6856。").font(.system(size: 10)).foregroundStyle(Theme.secondary) }
        }.padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .onChange(of: value) { _, color in hex = color.hexString }
    }
    private func applyHex() { if let parsed { value = parsed; hex = parsed.hexString } }
}
