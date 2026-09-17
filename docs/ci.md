# GitHub 自动检查

`.github/workflows/ci.yml` 在 PR 创建、重新打开、更新提交时，以及 `main` 收到推送时运行。检查名称为 **macOS build and tests**。这里只给出验证结果，合并决定仍由维护者作出。

工作流使用 GitHub 托管的 `macos-15` ARM runner，固定选择镜像内的 Xcode 16.4。Checkout 固定到 `actions/checkout` v7.0.1 的完整提交 SHA `3d3c42e5aac5ba805825da76410c181273ba90b1`；这些版本已在 2026-09-17 对照[官方镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)和[官方发布记录](https://github.com/actions/checkout/releases/tag/v7.0.1)确认。若日后镜像移除该 Xcode，需显式更新版本并验证，不静默切换工具链。

## 检查内容

1. `scripts/test.sh`：Core 和 CLI 单元测试。Socket 测试使用临时的合成数据和专用 Unix socket。
2. `scripts/test-apple-codec.sh`：编译真实 EventKit 日期桥接代码，只执行纯日期转换检查；不会建立 `EKEventStore` 或请求用户日历权限。
3. `scripts/build-app.sh`：Release 应用、CLI、配套 Skill 和知识资源打包。
4. 验证 Info.plist、必需资源以及 CLI 和应用的 ad-hoc 签名。签名通过不等于已完成 Apple 公证或 Developer ID 分发签名。

不在无人值守 CI 中运行 `test-cli-integration.py`，该检查需要已启动的隔离预览应用及原生窗口环境。GUI 操作、通知权限弹窗、真实 Apple 日历连接仍属于本地验收范围。

## 权限与数据范围

仅使用 `pull_request` 和 `push` 事件。默认 `GITHUB_TOKEN` 只有 `contents: read`，Checkout 不保留 Git 凭据，不引用仓库 Secrets。工作流没有合并、提交代码、创建 Release、发布应用或读取本机私有 Skill 的步骤；只依赖仓库里已提交的代码与合成测试夹具。外部贡献者的首次运行是否需要维护者批准，由仓库的 Actions 设置决定。[事件与 Fork PR 说明](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request)、[权限说明](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)

添加工作流不会自动建立分支保护。如需强制检查通过才能合并，可在仓库规则集中把 **macOS build and tests** 设为必需检查；本次实现没有修改仓库规则或合并权限。

## 验证状态

工作流编写阶段完成本地 YAML 解析和配置核对。GitHub 托管 runner 的执行结果必须以推送后 Actions 页面显示的实际运行结果为准，不能把本地测试通过表述成远程 CI 通过。
