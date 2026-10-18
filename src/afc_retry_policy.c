#include "afc_retry_policy.h"

#include <stddef.h>

static void clear_events(struct x2d_afc_retry_policy *p)
{
    unsigned i;

    for (i = 0; i < X2D_AFC_EVENT_CAPACITY; ++i)
        p->events[i].event = 0;
}

static void latch_fault(struct x2d_afc_retry_policy *p)
{
    p->fault = 1;
    x2d_afc_retry_cancel(p);
}

void x2d_afc_retry_init(struct x2d_afc_retry_policy *p)
{
    size_t i;
    unsigned char *bytes = (unsigned char *)p;

    for (i = 0; i < sizeof(*p); ++i)
        bytes[i] = 0;
}

void x2d_afc_retry_cancel(struct x2d_afc_retry_policy *p)
{
    p->pending = 0;
    p->active = 0;
    p->scan = 0;
    clear_events(p);
}

void x2d_afc_retry_hold(struct x2d_afc_retry_policy *p, unsigned held)
{
    held = held == 1;
    if (held != p->held) {
        if (p->hold == UINT64_MAX)
            p->fault = 1;
        else
            ++p->hold;
        x2d_afc_retry_cancel(p);
        p->held = held;
    }
}

int x2d_afc_retry_attempt(struct x2d_afc_retry_policy *p, unsigned eligible)
{
    x2d_afc_retry_cancel(p);
    if (p->fault || !p->held || eligible != 1)
        return 0;
    if (p->attempt == UINT64_MAX) {
        latch_fault(p);
        return 0;
    }

    ++p->attempt;
    p->active = 1;
    return 1;
}

int x2d_afc_retry_scan(struct x2d_afc_retry_policy *p, uint64_t scan)
{
    if (p->fault || !p->held || !p->active || p->pending ||
        !scan || scan <= p->scan)
        return 0;

    p->scan = scan;
    return 1;
}

int x2d_afc_retry_tag(struct x2d_afc_retry_policy *p, uintptr_t event,
                    unsigned raw, struct x2d_afc_event_tag *out)
{
    unsigned i, free_slot = X2D_AFC_EVENT_CAPACITY;
    struct x2d_afc_event_tag tag;

    if (p->fault || !p->held || !p->active || p->pending ||
        !p->scan || !event || raw > 4)
        return 0;

    for (i = 0; i < X2D_AFC_EVENT_CAPACITY; ++i) {
        if (p->events[i].event == event) {
            latch_fault(p);
            return -1;
        }
        if (!p->events[i].event && free_slot == X2D_AFC_EVENT_CAPACITY)
            free_slot = i;
    }
    if (free_slot == X2D_AFC_EVENT_CAPACITY || p->serial == UINT64_MAX) {
        latch_fault(p);
        return -1;
    }

    tag.event = event;
    tag.hold = p->hold;
    tag.attempt = p->attempt;
    tag.scan = p->scan;
    tag.serial = ++p->serial;
    tag.raw = raw;
    p->events[free_slot] = tag;
    if (out)
        *out = tag;
    return 1;
}

void x2d_afc_retry_forget(struct x2d_afc_retry_policy *p, uintptr_t event)
{
    unsigned i;

    for (i = 0; i < X2D_AFC_EVENT_CAPACITY; ++i) {
        if (p->events[i].event == event) {
            p->events[i].event = 0;
            return;
        }
    }
}

int x2d_afc_retry_take(struct x2d_afc_retry_policy *p, uintptr_t event,
                     unsigned raw, struct x2d_afc_event_tag *out)
{
    unsigned i;
    struct x2d_afc_event_tag tag = {0};

    for (i = 0; i < X2D_AFC_EVENT_CAPACITY; ++i) {
        if (p->events[i].event == event) {
            tag = p->events[i];
            p->events[i].event = 0;
            break;
        }
    }
    if (!tag.event || p->fault || !p->held || !p->active || p->pending ||
        tag.raw != raw || tag.hold != p->hold || tag.attempt != p->attempt ||
        tag.scan != p->scan || tag.serial <= p->consumed)
        return 0;

    p->consumed = tag.serial;
    if (out)
        *out = tag;
    return 1;
}

int x2d_afc_retry_fail(struct x2d_afc_retry_policy *p,
                     const struct x2d_afc_event_tag *tag,
                     unsigned eligible, unsigned raw)
{
    if (p->fault || !p->held || !p->active || p->pending ||
        eligible != 1 || raw != 2 || !tag || !tag->event ||
        !tag->scan || !tag->serial || tag->raw != 2 ||
        tag->hold != p->hold || tag->attempt != p->attempt ||
        tag->scan != p->scan || tag->serial != p->consumed)
        return 0;

    p->pending = 1;
    clear_events(p);
    return 1;
}

int x2d_afc_retry_rearm(struct x2d_afc_retry_policy *p, unsigned eligible)
{
    if (p->fault || !p->held || !p->active || !p->pending || eligible != 1) {
        if (eligible != 1)
            x2d_afc_retry_cancel(p);
        return 0;
    }

    p->pending = 0;
    p->active = 0;
    clear_events(p);
    return 1;
}
