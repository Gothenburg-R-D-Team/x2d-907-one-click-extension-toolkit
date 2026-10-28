# X2D/907 One-Click Extension Toolkit

[中文](#中文) · [English](#english)

---

## 中文

[项目简介](#zh-overview) · [安装（升级）前必读](#zh-before-installing) · [功能介绍](#zh-features) · [下载安装包](#zh-download) · [案例与恢复教程](#zh-cases) · [欢迎交流](#zh-community) · [许可](#zh-license)

<a id="zh-overview"></a>

### 项目简介

面向第一代 **X2D 100C / 907X & CFV 100C**、原厂固件 **4.2.0** 的实验性 Mac / Windows 扩展工具。本项目完全免费，是独立研究项目，非哈苏官方软件。

**最新公开版本：[0.5.6 · 恢复修复版 1](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6)（预发布）。** 针对已识别旧版安装的恢复失败，先等待拍摄结束、安全退出连续对焦并确认空闲，再执行严格撤回。

<a id="zh-before-installing"></a>

### 安装（升级）前必读

**相机已安装本工具扩展时，升级软件前务必、务必、务必先使用原电脑、原软件版本执行“一键恢复原状”，确认恢复完成后，再升级电脑端软件并重新安装相机扩展。** 恢复完成前，不要卸载、覆盖或删除原软件及备份。同版本跨电脑恢复的支持，不代表可以任意跨版本恢复。

- **首次安装**无需先恢复本工具的旧安装；仅使用明确支持的机型与原厂固件。
- **旧版恢复失败**时，可使用 0.5.6 恢复修复版 1 检查连接后直接恢复，无需先安装新版功能；仅支持已收录清单及完好、可核验的备份。
- **安装前阅读完整风险声明。** Mac／Windows 的三语言弹窗均要求滚动至末尾，再手动勾选确认；取消不启动相机操作。恢复使用独立提示。
- **安装、重启、校验和恢复期间保持供电与数据线连接**，直到 App 明确提示完成。
- 恢复只撤回本工具管理且可核验的改动，不能覆盖任意第三方补丁。检查未通过或恢复未完成时，保留原软件、安装记录和备份。

[完整升级顺序](docs/UPGRADING.md) · [中文风险告知与免责声明](docs/DISCLAIMER.zh-CN.md)

<details>
<summary>查看风险声明弹窗</summary>

以下为 0.5.6 Mac 原生弹窗的离线界面截图，展示尚未滚动至末尾时的禁用状态。界面检查不代表相机安装验证；Windows 原生显示验证仍待完成。

<img src="docs/images/risk-notice-0.5.6-zh.png" alt="0.5.6 Mac 简体中文风险声明弹窗，尚未滚动到底，确认框禁用" width="620">

</details>

<a id="zh-features"></a>

### 功能介绍

| 功能 | 说明 |
| --- | --- |
| AF-C 连续自动对焦 | 在相机中提供可选的连续对焦模式。 |
| 追踪自动对焦 | 提供 AF-T 人脸追踪对焦模式。 |
| 人眼识别 | 提供独立的人眼识别开关；选择 AF-T 时暂停该识别状态，返回 AF-S／AF-C 后按原开关选择恢复。 |
| 对焦加速 | 低／中／高三档可选，关闭后恢复原厂速度。 |
| 后屏自动亮度 | 根据环境光调整后屏亮度，可设置最高亮度。 |
| 像素位移 | **仅 X2D 100C**，通过驱动模式使用，支持 4／6／16 张 RAW 序列、初始延迟、帧间等待与倒计时提示；电脑合成需另行进行。 |

像素位移默认不勾选，使用前必须手动选择**纯 RAW**；JPEG 和 RAW+JPEG 均不满足要求。非 RAW 时参数及设置入口变灰，软件不自动修改照片格式。

未选择安装的功能不会出现在相机对应菜单中。相机菜单文案随安装时 App 语言变化：英文为 **Tweaks**，简体／繁体中文为 **耍起功能**。907 用户在机型核验后仍可选择原有彩蛋入口。

对焦加速可安装，但不建议老镜头用户在相机内开启该功能。档位倍率描述镜头电机控制参数，不代表实测整体对焦速度提升或镜头安全保证。

**已知未修复：眼部布局校验失败可能连带阻止追踪自动对焦开启。恢复修复版 1 只修恢复流程，相机载荷未改动；请勿反复重装同一版本尝试解决该问题。**

<a id="zh-download"></a>

### 下载安装包

**最新公开版本：0.5.6 · 恢复修复版 1（预发布）。**

| 平台 | 安装包 |
| --- | --- |
| macOS 13+ · Apple silicon / Intel | [**下载 Mac 通用版**](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/x2d-907-extension-toolkit-macOS-Universal-0.5.6-restore-fix-1.zip) |
| Windows 10 / 11 · x64 | [**下载 Windows x64 版**](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/x2d-907-extension-toolkit-Windows-x64-0.5.6-restore-fix-1.zip) |

**[支持开发](docs/SUPPORT.md)**

[发行说明](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6) · [SHA-256 校验](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/SHA256SUMS) · [验证记录](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/0.5.6.json) · [更新日志](CHANGELOG.md)

请从本页**手动下载并完整解压**后启动。App 启动时的更新检查不会自动下载安装此预发布版。Mac App 使用临时签名、未经公证；Windows 启动器未经代码签名。

**安装与恢复步骤**

1. 升级用户先按上面的要求使用原电脑、原软件版本完成恢复。首次安装可直接继续。
2. 完整解压对应平台安装包，开机并连接 USB 数据线；相机出现 **“跳过”** 时点击“跳过”。
3. 点击 **“已连接”**，等待型号、固件和文件检查完成。Windows 若出现管理员授权提示，请按提示处理。
4. 选择要安装的功能。907X／CFV 100C 不可选择像素位移；X2D 的像素位移默认不勾选。
5. 点击 **“安装所选功能”**，阅读完整风险声明、手动勾选并确认，保持连接直到 App 明确提示完成。
6. 在相机主菜单末尾打开 **“耍起功能”**，开启总开关及所需功能。像素位移从**驱动模式**进入，使用前手动选择**纯 RAW**；其序列需另在电脑合成。
7. 撤回时连接相机，点击 **“已连接 → 一键恢复原状”**，按独立恢复提示操作并等待完成。

App 设置提供简体中文、繁體中文和 English；更换相机菜单语言需要按升级／重新安装流程处理。

<details>
<summary>验证范围与限制</summary>

- 382 项离线回归中 **380 项通过、两项原厂区域仿真不可用**，未将跳过项计为通过。
- 另有 23 项界面／本地化回归、Mac 原生界面检查和 Windows 解压包 130 项回归通过。
- 补充验证 49 项恢复回归、1,369 个当前／旧版清单组合，以及 108 个桌面／文件恢复替身用例。
- Windows 原生运行、真实驱动安装、相机安装／恢复／拍摄和光学效果仍待相应实机验证。

具体记录与限制见 [0.5.6 验证记录](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/0.5.6.json)。

</details>

<a id="zh-cases"></a>

### 案例与恢复教程

[**浏览案例库**](docs/cases/README.md) · [**X2D II Wi-Fi 原厂固件恢复教程**](docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/README.md)

案例库按日期、机型与问题分别归档，包含原理、适用条件、操作步骤、脚本和验证结果，后续案例会持续加入。首个案例提供 Windows + 已授权 iPhone 的完整恢复流程，以及可打包下载的独立源码。

**X2D II 案例工具独立于一代桌面安装器；已记录一次用户操作成功，不代表支持所有故障或固件版本。**

<a id="zh-community"></a>

### 欢迎交流

欢迎分享使用反馈、研究发现，并通过 [Issues](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/issues) 讨论问题，或提交 [Pull Requests](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/pulls) 改进代码、文档与测试。公开日志前请移除个人信息。

贡献者保留各自贡献的版权，不要求版权转让。贡献授权、既有贡献许可和许可变更规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。

Git 中保存源码、测试、文档和软件截图；原厂固件、编译后的厂商组件、运行库与安装压缩包不提交到 Git。安装包以对应 [Release 附件](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6)为准；公开仓库当前源码与 0.5.6 安装包的构建源码并不同步。

<a id="zh-license"></a>

### 许可

本仓库采用下述 1.1 版许可；既有发行版继续适用其各自携带的许可。更新根目录许可不追溯改变历史权限或自动更改既有贡献的授权。

对于明确采用 [X2D/907 免费分发许可证 1.1](LICENSE) 的版本，允许免费使用、
研究、修改、构建和分享。禁止出售软件或改版、收费下载或访问、订阅、付费解锁、
付费专享或提前访问，以及收费安装、设置、配置或部署；不保留书面批准收费的例外。

**允许商业摄影、收费拍摄、影棚工作及出售摄影作品。** 照片及其他摄影成果不会
仅因使用本软件而受本许可证约束，也无需向项目支付费用或分成。

公开发布二进制安装包时，须同时免费公开对应版本的完整项目源码、构建脚本、
依赖信息和构建说明。通过链接提供源码的，应在最后一次分发该版本后至少保留三年。
内部开发和测试可以暂不公开；向测试者分发二进制时，仍须向其提供对应源码。
第三方组件和厂商固件保留各自许可，不因此承诺公开或再分发无权提供的材料。

官方承诺整个项目及未来功能持续免费，不提供收费授权。完全自愿且不换取软件权益
的捐赠可以接受。详见 [项目政策](PROJECT_POLICY.md)。

本项目属于带有收费分发限制的 **source-available（源码可获取）软件**，
并非采用 OSI 认可许可证的开源软件。历史 MIT 材料保留原有许可权限。
英文 [LICENSE](LICENSE) 为正式许可正文；本摘要仅供说明。

第三方组件的许可与来源见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

[返回顶部](#x2d907-one-click-extension-toolkit) · [English](#english)

---

## English

[Project overview](#en-overview) · [Read before installing or upgrading](#en-before-installing) · [Features](#en-features) · [Downloads](#en-download) · [Cases and recovery guides](#en-cases) · [Join the community](#en-community) · [License](#en-license)

<a id="en-overview"></a>

### Project overview

An independent, experimental Mac / Windows camera-extension utility for the first-generation **X2D 100C / 907X & CFV 100C**, running stock firmware **4.2.0**. Free to download and use. This is an independent research project, not an official Hasselblad product.

**Latest public release: [0.5.6 · Restore fix 1](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6) (prerelease).** It addresses restoration failures in recognized older installations by waiting for capture to finish, safely leaving continuous AF and verifying idle before guarded withdrawal.

<a id="en-before-installing"></a>

### Read before installing or upgrading

**If your camera already has this toolkit's extension, restore it using the original computer and original app version, and confirm completion before upgrading the desktop app and reinstalling the extension.** Keep the original app and backups until recovery is complete. Same-version recovery on another computer does not imply arbitrary cross-version recovery.

- **A first installation** does not require restoring a previous toolkit installation. Use only the stated camera models and stock firmware.
- **If an older toolkit cannot restore**, 0.5.6 Restore fix 1 can check the connection and restore directly without installing new features. Only registered manifests and intact, verifiable backups are supported.
- **Read the full risk notice before installation.** Both desktop apps offer three languages and require scrolling to the end, then explicitly checking the acknowledgement. Cancel starts no camera operation; Restore uses a separate prompt.
- **Keep the camera powered and connected** through installation, restart, verification and restoration until the app reports completion.
- Restore withdraws changes managed and verified by this tool; it cannot overwrite arbitrary third-party patches. If checks or recovery fail, keep the original app, installation records and backups.

[Upgrade procedure](docs/UPGRADING.md) · [Full risk notice and disclaimer](DISCLAIMER.md)

<details>
<summary>View the risk notice dialog</summary>

Native Mac 0.5.6 dialog captured during offline UI checks, before the end-of-document gate unlocks. Desktop UI checks do not establish camera-installation validation; native Windows display validation remains pending.

<img src="docs/images/risk-notice-0.5.6-en.png" alt="0.5.6 native Mac English risk notice with acknowledgement disabled before reaching the end" width="620">

</details>

<a id="en-features"></a>

### Features

| Feature | Behavior |
| --- | --- |
| Continuous Autofocus | Adds continuous autofocus as a selectable camera mode. |
| Tracking Autofocus | Adds an AF-T face-tracking focus mode. |
| Eye Recognition | Provides an independent Eye switch; selected AF-T pauses Eye, while AF-S / AF-C resumes it according to the saved choice. |
| Focus Speed Boost | Low / Medium / High levels; disabling restores stock speed. |
| Auto Rear Brightness | Adjusts rear-display brightness to ambient light, with a configurable maximum. |
| Pixel Shift | **X2D 100C only**: Drive Mode entry for 4 / 6 / 16 RAW sequences, initial delay, frame interval and countdown; desktop merging is separate. |

Pixel Shift is unchecked by default and requires manually selected **RAW**, without JPEG. JPEG and RAW+JPEG do not satisfy the requirement. Parameters and settings are disabled for non-RAW formats; the app does not change the photo format automatically.

Unselected features are omitted from the corresponding camera menus. Camera text follows the app language at installation: **Tweaks** in English, **耍起功能** in Simplified or Traditional Chinese. The existing optional 907 Easter egg remains available after model verification.

Focus Speed Boost can be installed, but users of older lenses are advised against enabling it in the camera. Its multipliers describe motor-control parameters, not measured overall autofocus gains or a lens-safety guarantee.

**Known unresolved issue: Eye layout validation failure can also block Tracking Autofocus activation. Restore fix 1 changes recovery preparation only; camera payloads are unchanged. Reinstalling the same build does not fix that issue.**

<a id="en-download"></a>

### Downloads

**Latest public release: 0.5.6 · Restore fix 1 (prerelease).**

| Platform | Download |
| --- | --- |
| macOS 13+ · Apple silicon / Intel | [**Download macOS Universal**](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/x2d-907-extension-toolkit-macOS-Universal-0.5.6-restore-fix-1.zip) |
| Windows 10 / 11 · x64 | [**Download Windows x64**](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/x2d-907-extension-toolkit-Windows-x64-0.5.6-restore-fix-1.zip) |

**[Support development](docs/SUPPORT.md)**

[Release notes](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6) · [SHA-256 checksums](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/SHA256SUMS) · [Validation record](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/0.5.6.json) · [Changelog](CHANGELOG.md)

**Download manually from this page and extract the entire ZIP** before opening the app. Startup update checks do not automatically download or install this prerelease. The Mac app uses an ad-hoc signature and is not notarized; the Windows launcher is unsigned.

**Installation and restoration**

1. Before upgrading, complete restoration with the original computer and app version as described above. First-time users can proceed directly.
2. Extract the complete package for your platform. Turn on the camera, connect a USB data cable and tap **Skip** if shown on the camera.
3. Click **Connected** and wait for model, firmware and file checks. Handle administrator prompts on Windows if requested.
4. Select the features to install. Pixel Shift is disabled on 907X / CFV 100C and unchecked by default on X2D.
5. Click **Install selected features**, read the full risk notice, explicitly check the acknowledgement and confirm. Keep connected until the app reports completion.
6. Open **Tweaks** at the end of the camera's main menu, enable the master switch and choose the required features. Pixel Shift is accessed through **Drive Mode** and requires manually selected **RAW**, without JPEG. Merge the resulting sequence separately on a computer.
7. To withdraw the extension, reconnect and use **Connected → Restore original**, following the separate recovery prompt until completion.

Settings offers Simplified Chinese, Traditional Chinese and English. Changing camera-menu text requires the restoration/reinstallation procedure.

<details>
<summary>Validation scope and limits</summary>

- **380 of 382 offline regressions pass; two unavailable stock-region simulations are not counted as passes.**
- Additional checks pass: 23 UI/localization regressions, native Mac UI checks and 130 extracted Windows regressions.
- Further validation covers 49 focused recovery regressions, 1,369 current/older manifest combinations and 108 host/file-restore fixture cases.
- Native Windows execution, actual driver installation, camera installation / restoration / capture and optical results still require the respective device validation.

See the [0.5.6 validation record](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/download/v0.5.6/0.5.6.json) for the exact evidence and limits.

</details>

<a id="en-cases"></a>

### Cases and recovery guides

[**Browse all cases**](docs/cases/README.md) · [**X2D II Wi-Fi firmware recovery**](docs/cases/2026-10-14-x2d-ii-wifi-firmware-recovery/README.md)

Each case has its own explanation, requirements, instructions, tools and evidence, organized by date, model and issue. The first guide provides the Windows + already-authorized iPhone recovery procedure and a portable source-package recipe; more cases can be added to the library.

**The X2D II case tools are separate from the first-generation desktop installer; one reported recovery does not establish support for every fault or firmware version.**

<a id="en-community"></a>

### Join the community

Feedback, research findings and developer contributions are welcome. Open an [Issue](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/issues) or submit a [Pull Request](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/pulls) to improve code, documentation and tests. Remove personal information before sharing logs publicly.

Contributors retain copyright; no assignment is required. Contribution licensing, existing-contribution and license-change rules are in [CONTRIBUTING.md](CONTRIBUTING.md).

Git contains source, tests, documentation and software screenshots; vendor firmware, compiled vendor components, runtimes and installer archives are excluded. Use the corresponding [Release assets](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit/releases/tag/v0.5.6) for installers; the public repository's current source does not yet match the 0.5.6 package build source.

<a id="en-license"></a>

### License

This repository uses the version 1.1 license below. Existing releases retain their accompanying licenses. Updating the root license does not retroactively change historical permissions or automatically relicense existing contributions.

Versions expressly released under the [X2D/907 No-Charge Distribution
License 1.1](LICENSE) may be used, studied, modified, built and shared without
charge. Selling the Software or modified versions, paid downloads or access,
subscriptions, paid unlocks, paid exclusive or early access, and paid
installation, setup, configuration or deployment are prohibited. There is no
written-permission exception for those charges under this license.

**Professional photography, paid shoots, studio work and selling photographs
are permitted.** Photographs and other photographic deliverables do not
become subject to this license merely through use of the Software, and no
project fee or revenue share is required.

Public binary releases must be accompanied by freely available corresponding
project source, build scripts, dependency information and build instructions.
Source provided through a link must remain available for at least three years
after the distributor's last distribution of that version. Private development
and testing need not be public, but recipients of private binaries must still
receive corresponding source. Third-party components and vendor firmware
retain their own licenses; this does not promise disclosure or redistribution
of materials the project has no right to provide.

The official project commits to keeping all its software and future features
free and to offering no paid software licenses. Fully voluntary donations that
purchase no software privileges are permitted. See [Project Policy](PROJECT_POLICY.md).

This is **source-available software with restrictions on software charges**,
not software under an OSI-approved open-source license. Historical MIT
materials retain their original permissions. The English [LICENSE](LICENSE)
is authoritative; this summary is informational.

Third-party licenses and provenance are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

[Back to top](#x2d907-one-click-extension-toolkit) · [中文](#中文)
