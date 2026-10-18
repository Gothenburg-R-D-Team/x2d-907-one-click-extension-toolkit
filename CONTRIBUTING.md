# X2D/907 One-Click Extension Toolkit — Contributing / 贡献规则

**Review draft — 18 October 2026. Not adopted.**

**供审阅草案——2026 年 10 月 18 日，尚未生效。**

These proposed rules apply to contributions to the
[X2D/907 One-Click Extension Toolkit](https://github.com/Gothenburg-R-D-Team/x2d-907-one-click-extension-toolkit).

本规则拟用于上述仓库中的 X2D/907 一键扩展功能工具包的项目贡献。

## 中文

### 1. 所有权与署名

贡献者保留其代码、文档、测试及其他原创贡献的版权，不要求版权转让。
贡献者可以说明希望使用的姓名或账号；维护者应保留适用的版权声明和合理署名，
准确标识贡献及第三方材料的来源。

### 2. 新贡献的明确授权

本规则正式采用后，拟以项目许可证发布的新原创贡献，应在 PR 中明确确认以下声明。
声明针对该次贡献，不代表转让版权，也不授权维护者在未来任意更换许可证：

> 我有权提交本次贡献。对于本 PR 中我原创且未另行标注许可的材料，我同意以
> X2D/907 No-Charge Distribution License 1.1 授权使用、修改和分发。
> 第三方材料及其适用许可已单独列明。我保留自己的版权，不进行版权转让。

贡献者应先阅读完整 [LICENSE](LICENSE) 和 [PROJECT_POLICY.md](PROJECT_POLICY.md)。
若贡献者不同意或需要另作约定，应在合并前提出并解决。未作明确声明不视为已同意
本草案；贡献审核和合并应等待许可澄清。

不得提交无权授权的他人代码、厂商固件、专有组件或其他受限材料。
引用或修改第三方材料时，须标明来源、版本、许可及必要声明；不应将第三方材料
错误标为本项目原创或用本许可证替换其原许可。

### 3. 既有贡献的许可

已经提交或合并的贡献不会因本文件发布而自动改变许可。维护者应核对贡献提交时
适用的许可、文件声明及已有明确约定，不推定所有旧贡献均采用同一种许可。

对需要变更许可的既有贡献，应向相关权利人展示完整拟用文本，明确指出涉及哪些
贡献，并取得可追溯的明确同意。未回复、继续讨论或既有合并不视为同意新许可。

无法就新许可取得必要授权时，不得声称相关贡献已经改用新许可；应评估在原许可
下保留、兼容集成、替换或从后续版本移除的具体方案，并保留应有声明。

### 4. 今后变更许可

提交 PR 不代表同意所有未来版本的许可证，也不授予维护者单方面改变他人代码
许可的权力。任何拟议变更应先核对现有授权，并在需要时取得相关权利人的明确同意。
历史 MIT 及其他许可已经授予的权限不得通过修改仓库文件追溯收回。

### 5. 审阅、整合与发布

贡献分支用于审阅、整合和测试。进入贡献分支不等于已经通过许可、安全或实机验证，
也不等于可以公开发布。在将贡献进一步集成到 `main` 或发布包前，应确认：

- 贡献来源、适用许可及必要授权明确，第三方声明完整；
- 改动已按实际风险完成适当审阅与验证，未验证事项和恢复限制已记录；
- 发布包对应源码、构建资料和版本标识准备齐全；
- 署名、许可、项目政策及发布说明一致。

临时测试或离线测试通过不应被表述为已完成相机实机验证。私人测试分发同样应遵守
[LICENSE](LICENSE) 的对应源码义务及接收者权利。

维护者无权授予尚未核实或不属于自己的权利。对许可或署名有疑问，可通过仓库
Issue、PR 或已有项目沟通渠道提出；确认前暂缓受影响贡献的进一步集成或发布。

## English

### 1. Ownership and credit

Contributors retain copyright in their original code, documentation, tests and
other contributions. No copyright assignment is required. Contributors may
state their preferred name or handle. Maintainers should preserve applicable
copyright notices and reasonable credit, and accurately identify the origin
of contributions and third-party materials.

### 2. Explicit licensing for new contributions

After these rules are adopted, a new original contribution intended for
release under the project license should include the following explicit PR
statement. It applies to that contribution, does not transfer copyright and
does not authorize arbitrary future relicensing:

> I have the right to submit this contribution. I agree to license the original
> materials I contribute in this PR, except materials expressly marked with a
> separate license, under the X2D/907 No-Charge Distribution License 1.1
> for use, modification and distribution. Third-party materials and their
> licenses are separately identified. I retain my copyright and make no
> copyright assignment.

Please read the complete [LICENSE](LICENSE) and
[PROJECT_POLICY.md](PROJECT_POLICY.md) first. Any disagreement or need for
different terms must be resolved before merge. The absence of an explicit
statement is not consent to this draft; licensing must be clarified before
review proceeds to merge.

Do not submit code, vendor firmware, proprietary components or other materials
you lack authority to contribute. Identify the origin, version, license and
required notices of third-party materials. Do not misidentify them as original
project work or replace their applicable licenses with the project license.

### 3. Licensing of existing contributions

Publishing this document does not automatically relicense submitted or merged
contributions. Maintainers must check the license applicable at submission,
file notices and express agreements rather than assume all earlier work has
the same licensing history.

Where a change requires permission, show the relevant rights holders the full
proposed text, identify the contributions affected and obtain a traceable,
explicit agreement. Silence, continued discussion or a previous merge is not
consent to a new license.

If necessary permission cannot be obtained, do not claim the contribution has
been relicensed. Assess whether to retain it under its existing terms,
integrate it compatibly, replace it or remove it from future versions, while
preserving required notices.

### 4. Future license changes

Submitting a PR is not agreement to all future license versions and does not
give maintainers unilateral authority to relicense someone else's work.
Proposed changes require checking existing permissions and obtaining explicit
agreement from relevant rights holders where necessary. Permissions already
granted under MIT or other licenses cannot be retroactively withdrawn by
changing repository files.

### 5. Review, integration and release

A contribution branch is used for review, integration and testing. A merge
into it is not approval of licensing, safety or device validation, and is not
release approval. Before further integration into `main` or a release,
maintainers should confirm that:

- Provenance, applicable licenses and necessary permissions are clear, with
  complete third-party notices.
- The change has received review and validation appropriate to its actual
  risks, with unverified behavior and recovery limits documented.
- Corresponding release source, build materials and version identification
  are ready.
- Attribution, licensing, policy and release notes are consistent.

Temporary testing or passing offline tests must not be described as completed
camera validation. Private test distributions must also comply with the
corresponding-source obligations and recipient rights in [LICENSE](LICENSE).

Maintainers cannot grant unverified rights or rights they do not hold. Raise
licensing or credit questions through an Issue, PR or an existing project
communication channel. Further integration or release of the affected
contribution should wait until those questions are resolved.
