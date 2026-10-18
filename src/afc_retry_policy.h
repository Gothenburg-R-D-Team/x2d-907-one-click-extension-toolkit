#ifndef X2D_AFC_RETRY_POLICY_H
#define X2D_AFC_RETRY_POLICY_H

#include <stdint.h>

#define X2D_AFC_EVENT_CAPACITY 64

/* An opaque, nonzero event identity and its originating generations.
 * The policy never dereferences event. raw is an adapter-verified result code:
 * this extracted protocol accepts 0..4, with 2 meaning AF failure. An adapter
 * must verify that mapping before using it with another result protocol. */
struct x2d_afc_event_tag {
    uintptr_t event;
    uint64_t hold, attempt, scan, serial;
    unsigned raw;
};

/* Public storage for allocation without a heap; fields are policy-owned.
 * A zero event marks a free slot. hold, attempt and serial never wrap or reset
 * on cancellation. scan belongs to an attempt; consumed is the most recent
 * successfully taken serial. fault remains set until explicit initialization.
 */
struct x2d_afc_retry_policy {
    uint64_t hold, attempt, scan, serial, consumed;
    unsigned held, active, pending, fault;
    struct x2d_afc_event_tag events[X2D_AFC_EVENT_CAPACITY];
};

/* Integration contract:
 * - All calls for one policy run on one owner thread, without reentrancy.
 *   There is no locking and this module cannot verify thread ownership.
 * - p must be non-NULL and initialized. Callers must not mutate its fields.
 *   Non-NULL output pointers must not overlap policy storage.
 * - real_held and eligible are true only when exactly 1. The adapter supplies
 *   a real physical half-press observation and rechecks all current eligibility
 *   gates; this policy neither synthesizes input nor discovers camera state.
 * - Cancellation is required when eligibility is lost. A new attempt begins
 *   only after the adapter observes a real attempt entry; a granted rearm is
 *   permission for the adapter to use its verified path, not an AF operation.
 * - The module performs no device access, transport, scheduling, sleeping,
 *   success-result mutation, retry-count limit or backoff.
 */

/* Initialize a new policy (or reset one after the adapter has invalidated all
 * old callbacks). This is the only operation that clears a latched fault. */
void x2d_afc_retry_init(struct x2d_afc_retry_policy *p);

/* Observe the physical half-press. Each edge invalidates the current attempt
 * and advances hold. Repeated observations of the same level do neither.
 * Exhausting the hold generation latches fault and cancels the attempt. */
void x2d_afc_retry_hold(struct x2d_afc_retry_policy *p, unsigned real_held);

/* Invalidate any previous attempt, then start one only while held and eligible.
 * Return 1 on entry, otherwise 0. Exhausting attempt latches fault. */
int x2d_afc_retry_attempt(struct x2d_afc_retry_policy *p, unsigned eligible);

/* Observe a real scan's nonzero identifier, strictly increasing within this
 * attempt. Return 1 when accepted, otherwise 0. The caller generates real_scan
 * and must prevent its own counter from wrapping; the policy never increments
 * it. Old-scan tags cannot be taken after a newer scan is accepted, but still
 * occupy their slots until take, forget or cancellation removes them. */
int x2d_afc_retry_scan(struct x2d_afc_retry_policy *p, uint64_t real_scan);

/* Retain provenance at verified result posting. Return 1 and optionally copy
 * the tag to out; return 0 for invalid/inactive/pending input. Duplicate live
 * identities, a full 64-slot table or exhausted serial latch fault, cancel all
 * retained tags and return -1. Identities may be reused after take/forget only
 * once the adapter has excluded outstanding callbacks for their old lifetime.
 */
int x2d_afc_retry_tag(struct x2d_afc_retry_policy *p, uintptr_t event,
                      unsigned raw, struct x2d_afc_event_tag *out);

/* Remove the retained tag for this identity, even if validation fails. Return
 * 1 and optionally copy to out only for current hold/attempt/scan, matching raw
 * and a serial newer than consumed. Thus replay and out-of-order older serials
 * return 0. out is unchanged on failure. No results are accepted while pending.
 */
int x2d_afc_retry_take(struct x2d_afc_retry_policy *p, uintptr_t event,
                       unsigned raw, struct x2d_afc_event_tag *out);

/* Discard an identity whose posting failed or whose lifetime ended. Unknown
 * identities are a no-op. This does not reset serial, pending or fault. */
void x2d_afc_retry_forget(struct x2d_afc_retry_policy *p, uintptr_t event);

/* After the adapter's normal result handler accepted a failure (raw == 2),
 * pass the unmodified tag from the latest successful take. Return 1 once per
 * attempt to set pending and invalidate all remaining tags. Return 0 for stale,
 * zero, replayed, ineligible or non-failure input. This is an ordering guard,
 * not authentication against a caller that fabricates or mutates policy data.
 */
int x2d_afc_retry_fail(struct x2d_afc_retry_policy *p,
                      const struct x2d_afc_event_tag *event,
                      unsigned eligible, unsigned raw);

/* At the adapter's verified reentry point, recheck eligibility. Return 1 once
 * for a pending failure while the same half-press is held, clearing active and
 * pending. The adapter must observe a new real attempt and scan before it can
 * accept more results. Ineligibility cancels; all other denials return 0.
 */
int x2d_afc_retry_rearm(struct x2d_afc_retry_policy *p, unsigned eligible);

/* Invalidate active/pending work, scan and all tags. Keep held and monotonic
 * generations, consumed serial and any fault; this never grants a retry. */
void x2d_afc_retry_cancel(struct x2d_afc_retry_policy *p);

#endif
