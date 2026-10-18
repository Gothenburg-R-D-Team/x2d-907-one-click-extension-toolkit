# AF-C failure-recovery policy / AF-C 失败恢复策略

## Scope

This contribution extracts a portable C decision policy from a separately
developed first-generation X2D 100C / firmware 4.2.0 AF-C experiment. It lets a
future runtime adapter request another stock AF round after an accepted failure
while the operator continues to hold the physical half press.

The module is not connected to the desktop app, camera menu, installer or camera
runtime in this PR. The public `main` source and the published 0.5.6 build source
are different; upstream integration must be reviewed against its actual source
and firmware. The policy is not evidence of a defect in the upstream runtime.

## Files and offline verification

- [`src/afc_retry_policy.h`](../src/afc_retry_policy.h): public state and API contract.
- [`src/afc_retry_policy.c`](../src/afc_retry_policy.c): pure state transitions.
- [`tests/test_afc_retry_policy.py`](../tests/test_afc_retry_policy.py): host regression entry.

From the repository root, with Python 3 and a host C11 compiler:

```sh
PYTHONPATH=src python3 -B -m unittest discover -s tests -p 'test_afc_retry_policy.py' -v
```

The tests compile the real policy into a temporary host executable. They use
synthetic event identities and sequences; they do not require firmware, a camera,
USB, network access, generated payloads or a desktop runtime. Compiler absence is
reported by the test runner, not counted as a passing policy check.

## Adapter contract

One verified owning thread must serialize all calls for one initialized policy.
The adapter retains ownership of real events, thread/receiver verification,
firmware identity, runtime state and cancellation. The policy only stores numeric
event identities and scalar generations; it never dereferences an event.

1. Observe the real physical half press with `x2d_afc_retry_hold`. Release cancels
   all pending recovery. Master-switch changes, mode changes, stop requests,
   exposure restrictions and loss of ownership must call `x2d_afc_retry_cancel`.
2. At a genuine accepted AF attempt, call `x2d_afc_retry_attempt` with freshly
   checked eligibility. Register each genuine scan using a positive, increasing
   scan identity; the adapter must not let its identity generator wrap.
3. Tag an actual AF-result event on its verified producer route, before handing
   ownership to the original dispatcher. Keep the original event unmodified.
4. On the matching consumer route, `x2d_afc_retry_take` consumes the saved tag
   exactly once. A mismatched result, old hold/attempt/scan, duplicate or
   out-of-order consumed serial cannot authorize recovery. A raw mismatch drops
   that tag, so replaying the same event with a corrected raw value still fails.
5. Preserve the original result handler, suppression windows and cleanup. Only
   an accepted ordinary failure may be passed to `x2d_afc_retry_fail` with the
   successfully consumed tag and freshly checked eligibility. Result code `2`
   means failure in this policy's donor contract; every adapter must explicitly
   validate or translate its own result enumeration. Other result codes do not
   schedule recovery.
6. After stock processing reaches its safe idle/re-entry barrier, check current
   eligibility again and call `x2d_afc_retry_rearm`. Its one-shot return value is
   permission for the adapter to request the original AF entry path; it is not
   an AF command. Register the next attempt through step 2. Failure to dispatch
   the request must cancel the policy.

The bounded 64-entry table, duplicate outstanding identities and internal counter
exhaustion latch a fault rather than guessing event ownership. A latched fault
requires explicit initialization after the adapter has drained the old event
lifecycle. The policy has no failure-count limit, timer, sleeping backoff,
synthetic key press, lens command, target selection or sound output.

## Evidence and remaining integration

The donor implementation corrected its own result-marker routing: the observed
result producer used a queued/post route, while its initial marker only covered
the send route. This contribution requires the real producer-to-consumer event
chain to be verified; it does not copy that firmware-specific hook implementation
or claim that the same routing defect exists in upstream code.

The extracted policy also rejects zero/unconsumed failure tags, stops accepting
new results while recovery is pending and latches exhausted attempt generations.
These are source-level hardening changes to the extraction, not a new deployed
camera version.

Host regressions establish the policy's ordering and cancellation behavior only.
No upstream device installation, firmware ABI, real Qt event routing, physical
half-press timing, optical refocus, sound, long-duration stability or recovery
procedure is validated by these tests. The donor application's operator feedback
does not validate this extracted module inside the upstream product.

## 中文交接

本次提交提供 AF-C 失败后恢复的独立策略源码、离线回归及接入契约，供作者在重构中审阅复用。
真实半按、事件来源、线程与所有权、原厂收尾和安全重入点都由运行时适配层核验；本模块只作
是否允许重试的决定，不操作相机。失败必须来自当前代次已消费的真实事件，松开、停用、模式
变化或曝光限制时取消。每次原厂收尾后只允许一次重入，不设失败次数或等待时限。

当前未接入上游 App，也未生成或提交相机载荷。离线测试通过只代表策略行为通过，不能作为
最新 0.5.6、私有重构分支或镜头实际重新合焦的验收。声音、人脸丢失重获和框响应优化留待
各自独立适配与审核。
