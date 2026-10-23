# New case checklist / 新案例结构

Use `docs/cases/YYYY-MM-DD-model-short-description/`. Add its entry to the case index.

| File | Contents / 内容 |
| --- | --- |
| `README.md` | Camera and firmware, fault, outcome, requirements, principle, links to steps/tools/evidence. 机型固件、症状、结果、条件、原理及操作／脚本／证据入口。 |
| `RECOVERY.en.md` / `RECOVERY.zh-CN.md` | Where to obtain tools and dependencies; exact working directory; actual commands or UI steps; expected outputs; stop conditions; completion checks. 下载、环境、运行目录、真实命令／界面步骤、预期结果、停止条件与完成验收。 |
| `CASE.md` | Timeline, observations versus operator reports and inferences, failed paths, outcome and missing evidence. 时间线、实测／用户反馈／推断、失败路线、结果及证据缺口。 |
| `PROVENANCE.json` or `MIGRATION.json` | Source commits, file hashes, adaptations, licensing and validation scope. 来源提交、哈希、改动、许可与验证范围。 |
| `VALIDATION.md` | Reproducible offline checks, device evidence, unverified conditions. 可复现离线检查、实机证据与未验证条件。 |

Keep runnable source in `src/tools/<case-or-method>/`, tests in `tests/`, and link them
from the case. Preserve original licenses when moving code. A portable package may be
generated from an explicit allowlist; do not include real session files, device IDs,
raw device logs, vendor firmware, proprietary App binaries or unrelated private materials.

脚本与测试分别按仓库目录规范放置，案例目录提供清楚入口。迁移代码保留原许可；
独立包使用明确的文件白名单，不包含真实会话、设备身份、原始机身日志、厂商固件／App 或无关私库资料。

Do not describe a prepared command as executed, a successful upload as a completed
installation, an offline test as a camera test, or one recovery as general compatibility.

不要把“已准备命令”写成“已执行”、上传成功写成安装完成、离线测试写成实机验证，或单次成功写成通用兼容。
