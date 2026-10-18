/* Host-only behavioral harness. No camera addresses, payloads or runtime. */
#include "afc_retry_policy.h"

#include <stdio.h>
#include <string.h>

#define CHECK(expression) do { \
    if (!(expression)) { \
        fprintf(stderr, "%s:%d: check failed: %s\n", __func__, __LINE__, #expression); \
        return 1; \
    } \
} while (0)

static int begin(struct x2d_afc_retry_policy *p, uint64_t scan) {
    x2d_afc_retry_init(p);
    x2d_afc_retry_hold(p, 1);
    return x2d_afc_retry_attempt(p, 1) == 1 && x2d_afc_retry_scan(p, scan) == 1;
}

static int deliver(struct x2d_afc_retry_policy *p, uintptr_t event,
                   unsigned raw, struct x2d_afc_event_tag *out) {
    return x2d_afc_retry_tag(p, event, raw, NULL) == 1 &&
           x2d_afc_retry_take(p, event, raw, out) == 1;
}

static int first_failure(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    CHECK(p.held == 1 && p.active == 0 && p.pending == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(deliver(&p, 2, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    return 0;
}

static int failure_after_success(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 10));
    CHECK(deliver(&p, 1, 1, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 1) == 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_scan(&p, 11) == 1);
    CHECK(deliver(&p, 2, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    CHECK(p.held == 1);
    return 0;
}

static int nonfailure_results(void) {
    const unsigned nonfailures[] = {0, 1, 3, 4};
    unsigned i;
    for (i = 0; i < sizeof(nonfailures) / sizeof(nonfailures[0]); ++i) {
        struct x2d_afc_retry_policy p;
        struct x2d_afc_event_tag result;
        CHECK(begin(&p, 1));
        CHECK(deliver(&p, 1, nonfailures[i], &result));
        CHECK(x2d_afc_retry_fail(&p, &result, 1, nonfailures[i]) == 0);
        CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
        CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
        CHECK(p.active == 1 && p.pending == 0);
    }
    return 0;
}

static int duplicate_delivery(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    return 0;
}

static int out_of_order(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag later;
    CHECK(begin(&p, 1));
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 2, &later) == 1);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &later, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    return 0;
}

static int old_scan(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag old, current;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &old));
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    CHECK(x2d_afc_retry_scan(&p, 2) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &old, 1, 2) == 0);
    CHECK(deliver(&p, 3, 2, &current));
    CHECK(x2d_afc_retry_fail(&p, &current, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    return 0;
}

static int old_attempt(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag old, current;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &old));
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &old, 1, 2) == 0);
    CHECK(deliver(&p, 3, 2, &current));
    CHECK(x2d_afc_retry_fail(&p, &current, 1, 2) == 1);
    return 0;
}

static int old_hold(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag old, current;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &old));
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    x2d_afc_retry_hold(&p, 0);
    x2d_afc_retry_hold(&p, 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &old, 1, 2) == 0);
    CHECK(deliver(&p, 3, 2, &current));
    CHECK(x2d_afc_retry_fail(&p, &current, 1, 2) == 1);
    return 0;
}

static int raw_mismatch(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 1, 1, NULL) == 0);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 0);
    CHECK(p.consumed == 0 && p.pending == 0);
    CHECK(deliver(&p, 2, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 1) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 3) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    return 0;
}

static int tag_metadata(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result, changed;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    changed = result; ++changed.hold;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    changed = result; ++changed.attempt;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    changed = result; ++changed.scan;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    changed = result; ++changed.serial;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    changed = result; changed.raw = 1;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    changed = result; changed.event = 0;
    CHECK(x2d_afc_retry_fail(&p, &changed, 1, 2) == 0);
    CHECK(x2d_afc_retry_fail(&p, NULL, 1, 2) == 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    return 0;
}

static int zero_tag(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result = {0};
    x2d_afc_retry_init(&p);
    x2d_afc_retry_hold(&p, 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    result.hold = p.hold; result.attempt = p.attempt; result.raw = 2;
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    result.scan = 1; result.event = 1;
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    return 0;
}

static int release(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    x2d_afc_retry_hold(&p, 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(p.pending == 0 && p.active == 0 && p.scan == 0);
    x2d_afc_retry_hold(&p, 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    return 0;
}

static int cancel(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    x2d_afc_retry_cancel(&p);
    CHECK(x2d_afc_retry_take(&p, 2, 2, NULL) == 0);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(p.held == 1 && p.pending == 0 && p.active == 0 && p.scan == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(deliver(&p, 3, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    x2d_afc_retry_cancel(&p);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    return 0;
}

static int attempt_cancellation(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_attempt(&p, 0) == 0);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 0);
    CHECK(p.pending == 0 && p.active == 0 && p.scan == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(deliver(&p, 2, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_attempt(&p, 0) == 0);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(deliver(&p, 3, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    return 0;
}

static int eligibility(void) {
    const unsigned ineligible[] = {0, 2, 255};
    unsigned i;
    for (i = 0; i < sizeof(ineligible) / sizeof(ineligible[0]); ++i) {
        struct x2d_afc_retry_policy p;
        struct x2d_afc_event_tag result;
        x2d_afc_retry_init(&p);
        x2d_afc_retry_hold(&p, 1);
        CHECK(x2d_afc_retry_attempt(&p, ineligible[i]) == 0);
        CHECK(x2d_afc_retry_scan(&p, 1) == 0);
        CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
        CHECK(x2d_afc_retry_scan(&p, 1) == 1);
        CHECK(deliver(&p, 1, 2, &result));
        CHECK(x2d_afc_retry_fail(&p, &result, ineligible[i], 2) == 0);
        CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
        CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
        CHECK(x2d_afc_retry_rearm(&p, ineligible[i]) == 0);
        CHECK(x2d_afc_retry_rearm(&p, 1) == 0);
        CHECK(p.pending == 0 && p.active == 0);
        CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    }
    return 0;
}

static int pending(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    uint64_t consumed;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_tag(&p, 2, 1, NULL) == 1);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    consumed = p.consumed;
    CHECK(x2d_afc_retry_scan(&p, 2) == 0);
    CHECK(x2d_afc_retry_tag(&p, 3, 2, NULL) == 0);
    CHECK(x2d_afc_retry_take(&p, 2, 1, NULL) == 0);
    CHECK(p.consumed == consumed && p.pending == 1);
    x2d_afc_retry_hold(&p, 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 1, NULL) == 0);
    return 0;
}

static int input_gates(void) {
    struct x2d_afc_retry_policy p;
    uint64_t hold;
    x2d_afc_retry_init(&p);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    CHECK(x2d_afc_retry_scan(&p, 1) == 0);
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 0);
    x2d_afc_retry_hold(&p, 2);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    x2d_afc_retry_hold(&p, 1);
    hold = p.hold;
    x2d_afc_retry_hold(&p, 1);
    CHECK(p.hold == hold);
    CHECK(x2d_afc_retry_scan(&p, 1) == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 0);
    CHECK(x2d_afc_retry_scan(&p, 0) == 0);
    CHECK(x2d_afc_retry_scan(&p, 10) == 1);
    CHECK(x2d_afc_retry_scan(&p, 10) == 0);
    CHECK(x2d_afc_retry_scan(&p, 9) == 0);
    CHECK(x2d_afc_retry_scan(&p, 11) == 1);
    x2d_afc_retry_hold(&p, 2);
    CHECK(p.held == 0 && p.active == 0);
    return 0;
}

static int capacity(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    unsigned i;
    CHECK(X2D_AFC_EVENT_CAPACITY == 64);
    CHECK(begin(&p, 1));
    for (i = 1; i <= 64; ++i) CHECK(x2d_afc_retry_tag(&p, i, 2, NULL) == 1);
    CHECK(p.fault == 0);
    for (i = 1; i <= 64; ++i) CHECK(x2d_afc_retry_take(&p, i, 2, &result) == 1);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    return 0;
}

static int capacity_overflow(void) {
    struct x2d_afc_retry_policy p;
    unsigned i;
    CHECK(begin(&p, 1));
    for (i = 1; i <= 64; ++i) CHECK(x2d_afc_retry_tag(&p, i, 2, NULL) == 1);
    CHECK(x2d_afc_retry_tag(&p, 65, 2, NULL) == -1);
    CHECK(p.fault == 1 && p.pending == 0 && p.active == 0 && p.scan == 0);
    for (i = 1; i <= 64; ++i) CHECK(x2d_afc_retry_take(&p, i, 2, NULL) == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    CHECK(x2d_afc_retry_scan(&p, 2) == 0);
    CHECK(x2d_afc_retry_tag(&p, 66, 2, NULL) == 0);
    x2d_afc_retry_hold(&p, 0);
    x2d_afc_retry_hold(&p, 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    return 0;
}

static int slot_reuse(void) {
    struct x2d_afc_retry_policy p;
    unsigned i;
    CHECK(begin(&p, 1));
    for (i = 1; i <= 64; ++i) CHECK(x2d_afc_retry_tag(&p, i, 2, NULL) == 1);
    x2d_afc_retry_forget(&p, 32);
    CHECK(x2d_afc_retry_take(&p, 32, 2, NULL) == 0);
    CHECK(x2d_afc_retry_tag(&p, 32, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_tag(&p, 65, 2, NULL) == 1);
    x2d_afc_retry_forget(&p, 999);
    CHECK(p.fault == 0);
    CHECK(x2d_afc_retry_take(&p, 32, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 65, 2, NULL) == 1);
    return 0;
}

static int duplicate_identity(void) {
    struct x2d_afc_retry_policy p;
    CHECK(begin(&p, 1));
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == -1);
    CHECK(p.fault == 1 && p.active == 0);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    return 0;
}

static int invalid_event(void) {
    struct x2d_afc_retry_policy p;
    CHECK(begin(&p, 1));
    CHECK(x2d_afc_retry_tag(&p, 0, 2, NULL) == 0);
    CHECK(x2d_afc_retry_tag(&p, 1, 5, NULL) == 0);
    CHECK(x2d_afc_retry_tag(&p, 1, (unsigned)-1, NULL) == 0);
    CHECK(p.serial == 0 && p.fault == 0);
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 0, 2, NULL) == 0);
    CHECK(x2d_afc_retry_take(&p, 999, 2, NULL) == 0);
    CHECK(x2d_afc_retry_take(&p, 1, 2, NULL) == 1);
    return 0;
}

static int output_unchanged(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag output, before;
    CHECK(begin(&p, 1));
    memset(&output, 0xa5, sizeof(output));
    memcpy(&before, &output, sizeof(before));
    CHECK(x2d_afc_retry_tag(&p, 0, 2, &output) == 0);
    CHECK(memcmp(&before, &output, sizeof(output)) == 0);
    CHECK(x2d_afc_retry_take(&p, 999, 2, &output) == 0);
    CHECK(memcmp(&before, &output, sizeof(output)) == 0);
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == 1);
    CHECK(x2d_afc_retry_take(&p, 1, 1, &output) == 0);
    CHECK(memcmp(&before, &output, sizeof(output)) == 0);
    CHECK(x2d_afc_retry_tag(&p, 2, 2, NULL) == 1);
    CHECK(x2d_afc_retry_scan(&p, 2) == 1);
    CHECK(x2d_afc_retry_take(&p, 2, 2, &output) == 0);
    CHECK(memcmp(&before, &output, sizeof(output)) == 0);
    return 0;
}

static int counter_overflow(void) {
    struct x2d_afc_retry_policy p;
    /* Boundary injection avoids 2^64 calls; all checks after it use the API. */
    x2d_afc_retry_init(&p);
    p.hold = UINT64_MAX;
    x2d_afc_retry_hold(&p, 1);
    CHECK(p.fault == 1 && p.hold == UINT64_MAX);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    CHECK(begin(&p, 1));
    p.attempt = UINT64_MAX;
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    CHECK(p.fault == 1 && p.attempt == UINT64_MAX && p.active == 0);
    CHECK(begin(&p, 1));
    p.serial = UINT64_MAX;
    CHECK(x2d_afc_retry_tag(&p, 1, 2, NULL) == -1);
    CHECK(p.fault == 1 && p.serial == UINT64_MAX && p.active == 0);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 0);
    return 0;
}

static int scan_boundary(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, UINT64_MAX));
    CHECK(x2d_afc_retry_scan(&p, 0) == 0);
    CHECK(x2d_afc_retry_scan(&p, UINT64_MAX) == 0);
    CHECK(deliver(&p, 1, 2, &result));
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
    CHECK(x2d_afc_retry_scan(&p, 1) == 1);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 0);
    CHECK(p.fault == 0);
    return 0;
}

static int repeated_failures(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    unsigned i;
    x2d_afc_retry_init(&p);
    x2d_afc_retry_hold(&p, 1);
    for (i = 1; i <= 512; ++i) {
        CHECK(x2d_afc_retry_attempt(&p, 1) == 1);
        CHECK(x2d_afc_retry_scan(&p, UINT64_MAX - i) == 1);
        CHECK(deliver(&p, i, 2, &result));
        CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
        CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
        CHECK(p.held == 1 && p.hold == 1 && p.fault == 0);
    }
    CHECK(p.attempt == 512 && p.serial == 512 && p.consumed == 512);
    return 0;
}

static int opaque_identity(void) {
    struct x2d_afc_retry_policy p;
    struct x2d_afc_event_tag result;
    CHECK(begin(&p, 1));
    CHECK(deliver(&p, (uintptr_t)1, 1, &result));
    CHECK(result.event == (uintptr_t)1);
    CHECK(deliver(&p, UINTPTR_MAX, 2, &result));
    CHECK(result.event == UINTPTR_MAX);
    CHECK(x2d_afc_retry_fail(&p, &result, 1, 2) == 1);
    CHECK(x2d_afc_retry_rearm(&p, 1) == 1);
    return 0;
}

struct test_case { const char *name; int (*run)(void); };

int main(int argc, char **argv) {
    const struct test_case cases[] = {
        {"first_failure", first_failure},
        {"failure_after_success", failure_after_success},
        {"nonfailure_results", nonfailure_results},
        {"duplicate_delivery", duplicate_delivery},
        {"out_of_order", out_of_order},
        {"old_scan", old_scan},
        {"old_attempt", old_attempt},
        {"old_hold", old_hold},
        {"raw_mismatch", raw_mismatch},
        {"tag_metadata", tag_metadata},
        {"zero_tag", zero_tag},
        {"release", release},
        {"cancel", cancel},
        {"attempt_cancellation", attempt_cancellation},
        {"eligibility", eligibility},
        {"pending", pending},
        {"input_gates", input_gates},
        {"capacity", capacity},
        {"capacity_overflow", capacity_overflow},
        {"slot_reuse", slot_reuse},
        {"duplicate_identity", duplicate_identity},
        {"invalid_event", invalid_event},
        {"output_unchanged", output_unchanged},
        {"counter_overflow", counter_overflow},
        {"scan_boundary", scan_boundary},
        {"repeated_failures", repeated_failures},
        {"opaque_identity", opaque_identity},
    };
    unsigned i;
    if (argc != 2) { fprintf(stderr, "Expected one test case name\n"); return 2; }
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i)
        if (strcmp(argv[1], cases[i].name) == 0) return cases[i].run();
    fprintf(stderr, "Unknown test case: %s\n", argv[1]);
    return 2;
}
