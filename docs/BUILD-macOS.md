# Mac 工具编译与构建

本文对应公开库的 **0.4.17 稳定版实现**，整理日期为 2026-10-12。软件基线为原始 v0.4.12，Mac App 面向 macOS 13 及以上，同时包含 `arm64` 和 `x86_64`。0.5.0 私有内测版的路径、材料和校验规则不能直接套用本文。

所有命令默认从仓库根目录执行。准备依赖可能联网；界面编译、材料校验和打包均可离线完成，不需要连接相机。

**已有相机扩展的用户，升级前务必、务必、务必先用原电脑、原软件版本恢复，确认完成后再升级软件。**同版本跨电脑恢复的支持不改变这一要求。构建新 App 不能替代这一步，具体见[升级指南](UPGRADING.md)与[免责声明](DISCLAIMER.zh-CN.md)。

## 1. 构建对象与完成条件

当前 App 的桌面界面是 Swift/Cocoa，使用 `swiftc` 编译；后台是随包分发的 Python 程序。没有需要打开的 `.xcodeproj`，也不采用 PyInstaller、Electron 或 PySide 来运行桌面界面。

| 目标 | 所需材料 | 结果 |
| --- | --- | --- |
| 编译和检查桌面界面 | 公开源码、macOS 开发工具、构建用 Python | 独立 Cocoa 检查 App，不带相机后台及完整运行库 |
| 构建完整 Mac 工具包 | 上述材料，以及 Python 运行库、PyUSB、libusb、ADB、完整相机材料和匹配的验证报告 | `.app`、分发 ZIP、校验文件、Mach-O 审计报告 |
| 复现已发布安装包的每一个字节 | 对应提交、相同全部输入及构建环境，还需控制归档时间戳等 | 本文和当前脚本不保证逐字节可复现 |

**仅克隆公开库，可以编译桌面界面并执行不依赖私有材料的测试；不能直接生成完整相机扩展工具包。**公开库保留部分清单和校验信息，不包含厂商固件、编译 QML、所有相机材料、第三方运行库及完整验证输入。

## 2. 相关源码

| 路径 | 职责 |
| --- | --- |
| [`src/MacApp.swift`](../src/MacApp.swift) | Cocoa 主窗口、设置、语言、后台任务和更新操作 |
| [`src/build_mac_app.py`](../src/build_mac_app.py) | 通用 App 编译、依赖搬移、签名、审计和 ZIP 打包入口 |
| [`src/stable_build_validation.py`](../src/stable_build_validation.py) | 三档速度版打包前的材料及报告门槛 |
| [`src/desktop-ui.json`](../src/desktop-ui.json) | 桌面布局和颜色 |
| [`src/translations.json`](../src/translations.json)、[`src/translations_zh_hant.json`](../src/translations_zh_hant.json) | 语言资源 |
| [`src/x2d_play_software.py`](../src/x2d_play_software.py) | 相机操作后台，桌面构建不执行设备操作 |
| [`src/app_updates.py`](../src/app_updates.py) | 更新检查、下载、校验、替换及回退 |
| [`src/MAC-READ-ME.txt`](../src/MAC-READ-ME.txt) | ZIP 内使用说明来源 |
| [`tests/check_stable_mac_desktop.py`](../tests/check_stable_mac_desktop.py) | 不携带后台的原生桌面控件检查副本 |

相机材料的准备另见[总体构建文档](BUILD.md)。本文重点是已准备好材料后的 Mac 桌面构建，不提供相机安装链或设备指令的替代步骤。

## 3. 开发工具与 Python 环境

准备 Command Line Tools 或配置正确的完整 Xcode。可用以下命令检查当前工具链：

```sh
xcode-select -p
xcrun --find swiftc
xcrun swiftc --version
xcrun --sdk macosx --show-sdk-path
command -v lipo otool install_name_tool codesign pkgutil
```

缺少开发工具时执行 `xcode-select --install`，按系统提示完成安装。本文构建不要求 `xcodebuild`；只安装 Command Line Tools 时，`xcodebuild -version` 报告需要完整 Xcode，不代表这里的 `swiftc` 构建不可用。

克隆并记录源码版本：

```sh
git clone https://github.com/radium-wang/x2d-907-one-click-extension-toolkit.git
cd x2d-907-one-click-extension-toolkit
git rev-parse HEAD
git status --short
```

使用 Python 3.9 或以上创建构建环境。这里运行脚本的 Python 与最终放进 App 的 Python 是两项不同输入：

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -B src/build_mac_app.py --help
```

[`requirements-dev.txt`](../requirements-dev.txt) 固定 `pyusb==1.3.1`、`pyelftools==0.32` 和 `capstone==5.0.6`。Qt 菜单及机器码专项验证还需要各自的额外环境，不包含在这三项中。

不带相机材料的源码测试：

```sh
PYTHONPATH=src .venv/bin/python -B -m unittest discover -s tests
```

检查最终汇总，区分通过、跳过和失败。缺少公开库未提供的材料时，相关用例会跳过；不能把跳过写成完整验证通过。[0.4.17 历史记录](STABLE-SPEED-TEST.md)中的 215 项完整测试是对应材料和当时源码的结果，不是执行上述命令必然获得的固定数字。

## 4. 只编译桌面界面

没有相机材料时，先构建不携带 Python 后台、USB、更新器或相机扩展的检查 App：

```sh
export X2D_MAC_UI_OUT="$PWD/src/outputs/mac-ui-build"
.venv/bin/python -B tests/check_stable_mac_desktop.py \
  --output "$X2D_MAC_UI_OUT" \
  --build-only
```

当前检查脚本固定编译 `arm64`；上述命令验证 Swift 编译和资源准备，不会自动打开窗口。输出包括 `StableDesktopCheck.app` 和经过检查脚本处理的 `main.swift`。

如需让这个检查副本也兼容 Intel，可基于同一份生成源码补编译 `x86_64` 并合并：

```sh
xcrun swiftc \
  -module-cache-path "$X2D_MAC_UI_OUT/swift-cache" \
  -target x86_64-apple-macos13.0 \
  "$X2D_MAC_UI_OUT/main.swift" \
  -o "$X2D_MAC_UI_OUT/Check-x86_64"

lipo -create \
  "$X2D_MAC_UI_OUT/StableDesktopCheck.app/Contents/MacOS/Check" \
  "$X2D_MAC_UI_OUT/Check-x86_64" \
  -output "$X2D_MAC_UI_OUT/Check-universal"

mv "$X2D_MAC_UI_OUT/Check-universal" \
  "$X2D_MAC_UI_OUT/StableDesktopCheck.app/Contents/MacOS/Check"
codesign --force --sign - "$X2D_MAC_UI_OUT/StableDesktopCheck.app"
lipo -archs "$X2D_MAC_UI_OUT/StableDesktopCheck.app/Contents/MacOS/Check"
```

应包含 `arm64` 和 `x86_64`。需要重做时，先用 `--build-only` 重新产生单架构副本，再执行合并，避免将已经合并的文件重复作为同一架构输入。

在已登录的 macOS 图形会话中，可从终端执行：

```sh
"$X2D_MAC_UI_OUT/StableDesktopCheck.app/Contents/MacOS/Check" --ui-smoke-test
```

此模式使用检查脚本生成的 Cocoa 点击逻辑，遍历三项功能的八种选择，包括空选，检查忙碌状态和三种语言，输出 `mac-zh.png`、`mac-zh-Hant.png`、`mac-en.png`，然后退出。成功标记为 `MAC_STABLE_UI_OK`。它不能验证 USB 通信、相机菜单、光学性能或完整工具包。

这里使用 `--build-only` 后直接启动可执行文件，不将检查脚本另一路生成的 `mac-ui-report.json` 作为完整包的 `--ui-report`。桌面控件检查和相机 Qt 菜单验证是不同的证据。

## 5. 完整工具包的运行库输入

当前已发布构建使用以下版本和约束；它们是本版输入，不表示各依赖的最新版本。更换版本后必须重新检查许可、架构、最低系统版本和运行行为。

| 输入 | 本版要求 | 官方来源／说明 |
| --- | --- | --- |
| App 内 Python | 官方 Python 3.13.15，普通 `3.13` framework，双架构 | [Python 3.13.15](https://www.python.org/downloads/release/python-31315/) |
| PyUSB | 1.3.1，`usb` 包目录及同级 dist-info 的 LICENSE | 由上述固定开发依赖安装 |
| libusb | 1.0.30，双架构动态库，最低 macOS 不高于 13.0 | [libusb v1.0.30](https://github.com/libusb/libusb/releases/tag/v1.0.30) |
| ADB | 官方 macOS Platform-Tools 的 `adb`，双架构，最低 macOS 不高于 13.0 | [Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools) |
| 许可文本 | Python 及所带组件、PyUSB、libusb、ADB 和项目许可 | 与实际使用的输入一起保留 |

ADB 的确切下载版本没有在 `build_mac_app.py` 中锁定。若复现某个发行包，应使用该次构建归档的 ADB 输入、版本及校验记录，不能用浮动的“最新下载”宣称复现了原包。

将输入放在受忽略的输出目录或仓库外。以下示例使用仓库内的本地目录：

```sh
export X2D_MAC_INPUTS="$PWD/src/outputs/mac-build-inputs"
mkdir -p "$X2D_MAC_INPUTS"
```

### 5.1 解包官方 Python

从官方页面下载 `python-3.13.15-macos11.pkg`，放入输入目录。包的官方 SHA-256 为：

```text
3b7eaf7f29825f796e8267024435540ddf1f17fc9a97ad58095daa7a75bfdcd3
```

核对下载文件后，展开到一个尚不存在的目标目录：

```sh
shasum -a 256 "$X2D_MAC_INPUTS/python-3.13.15-macos11.pkg"
pkgutil --expand-full \
  "$X2D_MAC_INPUTS/python-3.13.15-macos11.pkg" \
  "$X2D_MAC_INPUTS/python-expanded"

export X2D_MAC_PYTHON_FRAMEWORK="$X2D_MAC_INPUTS/python-expanded/Python_Framework.pkg/Payload"
test -f "$X2D_MAC_PYTHON_FRAMEWORK/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"
test -d "$X2D_MAC_PYTHON_FRAMEWORK/Versions/3.13/lib/python3.13"
test -f "$X2D_MAC_INPUTS/python-expanded/Python_Documentation.pkg/Payload/_sources/license.rst.txt"
test -f "$X2D_MAC_INPUTS/python-expanded/Resources/License.rtf"
```

`--python-framework` 要传入包含 `Versions/3.13` 的 framework 根目录。在这个展开布局中，它就是 `Python_Framework.pkg/Payload`，不要再拼接一个不存在的 `Python.framework`。保留同级的文档包和 `Resources/License.rtf`：当前构建器还会从该布局复制第三方许可。展开操作不需要安装该 pkg 或执行它的安装脚本。

也可以使用 `--python /path/to/python3.13` 替代 `--python-framework`，两者不能同时传入。该入口只适用于具有构建器预期的 framework 布局、双架构依赖和许可材料的 Python；不能假定系统 Python、任意 venv 或单架构 Homebrew Python 都满足条件。优先使用上面的官方解包方案。

### 5.2 准备 libusb

现成单架构 Homebrew 动态库不满足通用 App 的要求。若没有本版已验证的双架构输入，可从官方 **1.0.30 发布源码归档**开始构建，使用包含 `configure` 的发布归档，而非缺少生成文件的任意源码快照。

将归档展开到 `$X2D_MAC_INPUTS/libusb-1.0.30` 后，可参考当前输入使用的编译方式：

```sh
(
  set -eu
  cd "$X2D_MAC_INPUTS/libusb-1.0.30"
  export MACOSX_DEPLOYMENT_TARGET=13.0
  CFLAGS='-O2 -arch arm64 -arch x86_64 -Werror=unguarded-availability-new' \
  LDFLAGS='-arch arm64 -arch x86_64' \
    ./configure --prefix="$X2D_MAC_INPUTS/libusb-macos13" \
      --disable-static --enable-shared
  make
  make install
)

export X2D_MAC_LIBUSB="$X2D_MAC_INPUTS/libusb-macos13/lib/libusb-1.0.dylib"
export X2D_MAC_LIBUSB_LICENSE="$X2D_MAC_INPUTS/libusb-1.0.30/COPYING"
lipo -archs "$X2D_MAC_LIBUSB"
otool -l "$X2D_MAC_LIBUSB"
```

保留输出及实际输入哈希。`lipo` 应报告两个架构；`otool -l` 中各架构的 `LC_BUILD_VERSION/minos` 或 `LC_VERSION_MIN_MACOSX/version` 必须不高于 13.0。设置编译变量后仍要核验产物，不能仅凭命令中的 `13.0` 宣称已经兼容。

### 5.3 准备 ADB 与 PyUSB

完整解压官方 macOS Platform-Tools，将 `platform-tools` 放在输入目录下，并保留 `adb` 旁的 `NOTICE.txt`：

```sh
export X2D_MAC_ADB="$X2D_MAC_INPUTS/platform-tools/adb"
test -x "$X2D_MAC_ADB"
test -f "$X2D_MAC_INPUTS/platform-tools/NOTICE.txt"
lipo -archs "$X2D_MAC_ADB"
otool -l "$X2D_MAC_ADB"

export X2D_MAC_PYUSB="$(.venv/bin/python -c 'from pathlib import Path; import usb; print(Path(usb.__file__).resolve().parent)')"
test -f "$X2D_MAC_PYUSB/__init__.py"
```

`--pyusb` 指向 `usb` 包目录，不是 wheel、ZIP 或整个 `site-packages`。保持安装后的目录结构，构建器通过 `usb` 上一级目录中的 `pyusb-*.dist-info/LICENSE` 获取许可。

## 6. 完整相机材料与报告门槛

准备已经完成校验的 **0.4.17 完整相机材料目录**及其匹配的原厂 Qt 菜单验证报告。下列路径是占位示例，必须替换为本机的真实绝对路径：

```sh
export X2D_PAYLOAD_DIR='/absolute/path/to/verified-0.4.17-payload'
export X2D_MAC_UI_REPORT='/absolute/path/to/verified-qt-menu/validation.json'
```

不设置 `X2D_PAYLOAD_DIR` 时，构建器默认读取 `src/native-package`；公开库中的这个目录只有部分文本清单，不能据此假定完整材料已经具备。

完整输入至少包含：

- 当前 `speed-bundle.json`、`speed-bundle.tar.gz`，清单 `files` 和各 `uiLanguages` 中列出的全部文件。
- 构建器明确列出的历史恢复清单、`previous-speed-server.so` 及完整 `previous-payloads` 目录。仅提供当前文件会在复制恢复材料时失败。
- `speed-machine-validation.json`，以及与当前清单哈希一致的 Qt 菜单报告。

`stable_build_validation.require_tested_payload()` 对带 `speedLevels` 的材料执行以下门槛：

| 门槛 | 当前代码检查 |
| --- | --- |
| 菜单报告对应当前输入 | `payloadManifestSha256` 等于 `speed-bundle.json` 的 SHA-256 |
| 使用实际视觉控件 | `visualMocks` 为 `false`，`deviceAccessed` 为 `false` |
| 菜单结构 | 七种非空选择、原有行与基线一致、速度选项紧邻加速项 |
| 三档选择 | low / medium / high，zh / zh-Hant / en；选择回读、失败保留、键盘返回、禁用状态、原厂纵向选择器、滑动及高亮等检查通过 |
| 机器码报告 | `PASS`、4,206 个用例、不访问设备，三档 profile 哈希匹配清单 |

先单独运行这个门槛，便于将材料问题与打包问题分开：

```sh
PYTHONPATH=src .venv/bin/python -B - <<'PY'
import os
from pathlib import Path
from stable_build_validation import require_tested_payload

require_tested_payload(
    Path(os.environ['X2D_PAYLOAD_DIR']),
    Path(os.environ['X2D_MAC_UI_REPORT']),
)
print('STABLE_PAYLOAD_GATE_OK')
PY

PYTHONPATH=src .venv/bin/python -B -m unittest discover -s tests
```

第二条命令继承已导出的 `X2D_PAYLOAD_DIR`。报告门槛不是全部测试的替代品，也不是实机验证。

如需要重新生成报告，真实菜单入口为 [`tests/check_stable_speed_ui.py`](../tests/check_stable_speed_ui.py)，要求 Qt 6.4.1、原厂 UI 输入、字体、原始 v0.4.12 基线材料及当前材料；输出为 `validation.json`。机器码入口为 [`tests/check_speed_machine.py`](../tests/check_speed_machine.py)，还需 Unicorn 和固定原厂库，输出到材料目录中的 `speed-machine-validation.json`。这些输入和环境不由普通桌面打包自动产生，说明见[总体构建文档](BUILD.md)及[验证记录](STABLE-SPEED-TEST.md)。不要手写报告、修改成功字段或删除门槛来绕过验证。

## 7. 构建完整 Mac App

确认前文变量和材料都已准备。选择独立的新输出目录；脚本会删除该输出目录内同名旧 `.app` 并重建，所以不要将输出指向正在使用的安装位置或原版本恢复工具：

```sh
export X2D_MAC_OUT="$PWD/src/outputs/mac-local-0.4.17"

.venv/bin/python -B src/build_mac_app.py \
  --python-framework "$X2D_MAC_PYTHON_FRAMEWORK" \
  --adb "$X2D_MAC_ADB" \
  --libusb "$X2D_MAC_LIBUSB" \
  --libusb-license "$X2D_MAC_LIBUSB_LICENSE" \
  --pyusb "$X2D_MAC_PYUSB" \
  --ui-report "$X2D_MAC_UI_REPORT" \
  --output "$X2D_MAC_OUT"
```

`X2D_PAYLOAD_DIR` 必须在启动脚本前导出；脚本在模块加载时读取它。所有路径带引号，支持目录名含空格或中文。该命令不连接相机，不安装扩展，也不发布 GitHub Release。

当前构建器依次：

1. 检查相机材料及匹配的菜单、机器码报告。
2. 复制 Python 3.13 运行库，排除测试、Tk 和无关 `site-packages`；单独复制 PyUSB、后台脚本、语言资源、ADB 和 libusb。
3. 复制当前扩展及历史恢复材料。
4. 用 `otool` 递归解析非系统 Mach-O 依赖，复制到包内，并用 `install_name_tool` 改为 `@loader_path` 相对引用。
5. 检查 Python、ADB、libusb 及其他复制的 Mach-O 文件同时包含两个架构，且最低系统版本不高于 macOS 13.0。
6. 分别以 `arm64-apple-macosx13.0` 和 `x86_64-apple-macosx13.0` 编译 `MacApp.swift`，用 `lipo` 合并为 `X2DPlay`。
7. 写入 `Info.plist`、复制许可、对内部动态库和 App 执行 ad-hoc 签名，并校验签名。
8. 用包内 Python 执行模块导入和动态库加载检查，打印 `PACKAGED_RUNTIME_OK`。
9. 再次审计包内依赖，生成报告、ZIP 和 SHA-256 文件。

不能只把主可执行文件合并成双架构，就声称整个 App 已支持 Intel 和 Apple 芯片；后台 Python、扩展模块、ADB 和每项非系统动态库也必须满足要求。[Apple 通用二进制说明](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)。

## 8. 输出结构

```text
src/outputs/mac-local-0.4.17/
├── x2d-907一键扩展功能-工具包.app/
│   └── Contents/
│       ├── Info.plist
│       ├── MacOS/X2DPlay
│       └── Resources/
│           ├── runtime/bin/python3.13
│           ├── runtime/lib/
│           ├── bin/adb
│           ├── lib/libusb-1.0.dylib
│           ├── usb/
│           ├── native-package/
│           ├── licenses/
│           ├── desktop-ui.json
│           ├── translations.json
│           ├── translations_zh_hant.json
│           ├── x2d_play_software.py
│           └── app_updates.py
├── X2DPlay-arm64
├── X2DPlay-x86_64
├── macOS-compatibility-audit.json
├── 使用说明-macOS.txt
├── x2d-907-extension-toolkit-macOS-Universal-0.4.17.zip
└── SHA256.txt
```

结构为主要文件示意，实际还含恢复确认等后台文件和 Swift 模块缓存。ZIP 只包含使用说明及 `.app`；审计 JSON、临时架构文件和 `SHA256.txt` 保留在输出目录，需单独归档。

App 内部带运行库和已搬移的非系统依赖；使用者无需安装 Python 或 Homebrew。构建器使用的是 `codesign --sign -` 的 ad-hoc 签名，**没有 Developer ID 签名和 Apple 公证流程**，成功的本地签名验证不代表公证完成。

## 9. 构建后的核验

### 9.1 静态核验

```sh
export X2D_MAC_APP="$X2D_MAC_OUT/x2d-907一键扩展功能-工具包.app"

codesign --verify --deep --strict "$X2D_MAC_APP"
lipo -archs "$X2D_MAC_APP/Contents/MacOS/X2DPlay"
plutil -p "$X2D_MAC_APP/Contents/Info.plist"

(
  cd "$X2D_MAC_OUT"
  shasum -a 256 -c SHA256.txt
)
```

本版应有 `CFBundleIdentifier=local.x2d.play`、`CFBundleShortVersionString=0.4.17`、`LSMinimumSystemVersion=13.0`，并保留用于追溯的 `X2DSoftwareBaseline=v0.4.12` 和 `X2DLocalBuild=stable-speed-test-1`。当前脚本将 `CFBundleVersion` 写为 `27`；它不是从 Git 自动生成的编号。

检查 `macOS-compatibility-audit.json` 中每个条目的 `architectures`、`minimumVersions` 和 `dependencies`。非系统依赖应全部在 App 内解析，不再依赖构建机的 `/opt/homebrew` 或 `/Library/Frameworks`。

### 9.2 包内运行库核验

下面仅导入模块及加载本地动态库，不枚举 USB 或操作相机：

```sh
env -u X2D_PAYLOAD_DIR \
  PYTHONHOME="$X2D_MAC_APP/Contents/Resources/runtime" \
  PYTHONPATH="$X2D_MAC_APP/Contents/Resources" \
  PYTHONNOUSERSITE=1 \
  "$X2D_MAC_APP/Contents/Resources/runtime/bin/python3.13" -B - <<'PY'
import ctypes
import json
import os
from pathlib import Path
import ssl
import usb.core

resources = Path(os.environ['PYTHONPATH'])
ctypes.CDLL(str(resources / 'lib/libusb-1.0.dylib'))
print('PACKAGED_RUNTIME_OK', ssl.OPENSSL_VERSION)
PY
```

### 9.3 界面与平台核验

完整 App 可在图形会话中执行现有短暂启动检查：

```sh
"$X2D_MAC_APP/Contents/MacOS/X2DPlay" --ui-smoke-test
```

该参数跳过正常启动的自动更新检查，约两秒后退出；仍会使用正常 App 的本地设置及日志目录。不要把它当成隔离的桌面点击测试。完整 App 的普通启动可能进行联网更新检查；点击连接、安装或恢复又是其他设备操作。

签名、架构和当前机器启动检查通过后，仍需在实际 Intel 与 Apple 芯片 Mac、声明支持的系统版本上验证。Apple 芯片上的 Intel 转译测试或 Mach-O 静态检查，不能单独证明全部 Intel 机器和 macOS 13 实机行为。相机安装、恢复及光学功能另行验证，不能由桌面构建结果代替。

## 10. 改版本与分发

当前版本不是命令行参数；`build_mac_app.py` 中的 `VERSION='0.4.17'` 与其他源码、材料清单、`Info.plist`、使用说明及更新器命名约定必须一致。仅改 ZIP 文件名或 `VERSION` 不会生成已经验证的新功能版本。

本地构建用于开发测试。计划正式分发时，应单独检查：

- 对应提交和实际输入的版本、哈希及许可；相机材料必须与报告一致。
- 中文、繁体、英文资源；当前已知问题及真实平台验证范围。
- `MAC-READ-ME.txt` 的说明是否准确反映本版。历史遗留文案不能因脚本复制成功就被当成当前功能事实。
- [中英免责声明](../DISCLAIMER.md)和[升级前恢复要求](UPGRADING.md)的入口。**当前脚本不会自动把新免责声明复制到 App 或接入更新弹窗**，这些文档已公开不表示二进制已接入。
- 当前许可证和 [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md)；有条件复制的 Python、ADB 等许可文件实际存在。
- 解压后签名、ZIP 权限和更新器识别检查；相同版本、旧版本和不符合命名的本地 ZIP 不应被假定为自动更新发行包。

源代码、文档和测试可按项目许可提交；厂商派生相机材料、运行库、设备日志和生成安装包保留在忽略目录，不混入源码提交。发布是独立操作，不由编译命令自动执行。使用者升级时仍须先用原电脑原版本恢复。

## 11. 常见构建问题

| 报错或现象 | 检查方向 |
| --- | --- |
| 找不到 `swiftc`、SDK 或系统工具 | 检查 Command Line Tools、`xcode-select -p` 和 `PATH` |
| 找不到 `speed-bundle.json` 或某个 `.so` | `X2D_PAYLOAD_DIR` 是否导出，是否真的是完整材料，而非公开清单目录 |
| `Stable speed packaging requires native UI evidence` | 提供真实 Qt 菜单 `validation.json`，不是 Cocoa 桌面报告 |
| `Stable UI evidence does not match payload` | 核对当前清单 SHA-256、视觉控件及设备访问字段，不改报告伪造通过 |
| `Stable machine-code checks incomplete`／profile mismatch | 对应机器码报告缺失、失败或与当前三档材料不一致 |
| 缺少 Python 许可或 `Versions/3.13` | 传入完整官方展开布局，选择普通 `3.13`，不是 `3.13t` |
| `Missing universal architecture` | 某个输入只有一项架构；检查 Python、ADB、libusb 及传递依赖 |
| `Dependency requires newer macOS`／`Invalid deployment target` | 某个输入最低系统高于 13.0，需替换或重新构建该输入 |
| `Unresolved rpath dependency`／`Unsupported dependency` | 动态库的源依赖不在解析器支持的路径，先检查 `otool -L` 和 `otool -l` |
| `Dependency filename collision` | 不同依赖同名，不能盲目覆盖，需核对源库及引用关系 |
| PyUSB 的 `StopIteration` 或许可文件缺失 | `--pyusb` 指向 `usb`，上一级应保留 dist-info 的 LICENSE |
| `PACKAGED_RUNTIME_OK` 未出现或导入报错 | 检查运行库搬移、架构、Python 标准库及包内动态库路径 |
| 重新构建后签名失败 | 包内文件被修改或签名顺序不对，回到构建步骤重做；不能在签名后直接修改资源 |
| Qt 专项检查无法运行 | 它有独立 Qt 6.4.1 及原厂输入要求，不是 Cocoa 编译失败；见总体构建文档的 Intel／Rosetta 说明 |

记录实际命令、提交、工具版本、输入哈希、通过及跳过数量和完整错误上下文。公开反馈前先移除个人路径、设备身份及不必要日志。

## 12. 本文命令核验记录

2026-10-12 在 macOS 27.0、Apple Swift 6.4、构建用 Python 3.9.6 环境下，以公开源码提交 `8bef579` 的 App 实现核验本文。本次只添加文档，核验生成物保留在本地忽略目录。

- 17 段 shell 示例通过 zsh 语法检查；文档相对链接检查通过。
- Cocoa 检查副本的 arm64、x86_64 编译和通用文件合并、签名校验通过；本次没有执行其图形会话点击检查。
- 使用现有完整 0.4.17 材料及匹配的既有 Qt 菜单报告，离线构建完整 `.app` 与 ZIP 成功。
- 包内 Python 3.13.15、PyUSB、SSL 导入及 libusb 加载通过；76 个 Mach-O 文件的双架构、部署目标和包内依赖检查通过，App 签名及 ZIP SHA-256 校验通过。
- 公开源码测试发现 215 项，174 项通过、41 项因缺少相应输入跳过，无失败。这次源码测试没有使用完整相机材料替代默认输入，不能记为 215 项全部执行通过。

本次没有连接、安装、恢复或重启相机，没有重新完成 Intel 实机、macOS 13 实机或相机功能验证，也没有替换已发布的安装包。依赖准备中的下载、重新编译 libusb 及全套 Qt／机器码证据再生成步骤，未在此次文档核验中重新执行。
