"""Host-only behavioral checks of the standalone C AF-C retry policy.

This module compiles the real policy with the host C compiler. It imports no
application runtime and performs no transport, device, or firmware operations.
"""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AfcRetryPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shlex.split(os.environ.get("CC", "cc"))
        if not compiler or shutil.which(compiler[0]) is None:
            raise unittest.SkipTest("A host C compiler is required for the AF-C policy checks")
        temporary = tempfile.TemporaryDirectory(prefix="x2d-afc-policy-")
        cls.addClassCleanup(temporary.cleanup)
        cls.executable = Path(temporary.name) / "afc-retry-policy-tests"
        command = compiler + [
            "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-I", str(ROOT / "src"),
            str(ROOT / "src" / "afc_retry_policy.c"),
            str(ROOT / "tests" / "afc_retry_policy_host_test.c"),
            "-o", str(cls.executable),
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError("Host C compilation failed:\n" + result.stdout + result.stderr)

    def run_case(self, case):
        result = subprocess.run(
            [str(self.executable), case], capture_output=True, text=True, timeout=10
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_first_failure_is_consumed_and_rearms_without_releasing(self):
        self.run_case("first_failure")

    def test_failure_after_success_rearms_without_releasing(self):
        self.run_case("failure_after_success")

    def test_every_nonfailure_result_is_excluded(self):
        self.run_case("nonfailure_results")

    def test_result_and_rearm_can_each_be_consumed_only_once(self):
        self.run_case("duplicate_delivery")

    def test_out_of_order_delivery_cannot_replay_an_older_result(self):
        self.run_case("out_of_order")

    def test_new_scan_rejects_queued_and_consumed_old_scan_results(self):
        self.run_case("old_scan")

    def test_new_attempt_rejects_old_attempt_results(self):
        self.run_case("old_attempt")

    def test_new_hold_rejects_old_hold_results(self):
        self.run_case("old_hold")

    def test_mismatched_raw_result_is_discarded(self):
        self.run_case("raw_mismatch")

    def test_failure_requires_matching_taken_tag_metadata(self):
        self.run_case("tag_metadata")

    def test_zero_tag_cannot_arm_before_any_result_is_taken(self):
        self.run_case("zero_tag")

    def test_release_cancels_pending_recovery(self):
        self.run_case("release")

    def test_explicit_cancel_invalidates_results_and_pending_recovery(self):
        self.run_case("cancel")

    def test_new_attempt_cancels_prior_pending_and_outstanding_results(self):
        self.run_case("attempt_cancellation")

    def test_eligibility_must_be_exactly_one(self):
        self.run_case("eligibility")

    def test_pending_failure_excludes_additional_scan_and_result_delivery(self):
        self.run_case("pending")

    def test_hold_and_scan_require_real_eligible_inputs(self):
        self.run_case("input_gates")

    def test_all_64_event_slots_are_usable(self):
        self.run_case("capacity")

    def test_65th_outstanding_event_latches_fault_and_clears_slots(self):
        self.run_case("capacity_overflow")

    def test_forget_and_take_free_slots_for_new_events(self):
        self.run_case("slot_reuse")

    def test_duplicate_outstanding_event_identity_latches_fault(self):
        self.run_case("duplicate_identity")

    def test_invalid_event_inputs_do_not_use_slots_or_serials(self):
        self.run_case("invalid_event")

    def test_rejected_event_does_not_modify_output_tag(self):
        self.run_case("output_unchanged")

    def test_hold_attempt_and_serial_counter_overflow_fail_closed(self):
        self.run_case("counter_overflow")

    def test_scan_counter_boundary_is_supplied_by_caller(self):
        self.run_case("scan_boundary")

    def test_512_failures_do_not_exhaust_a_retry_count_limit(self):
        self.run_case("repeated_failures")

    def test_event_identities_are_opaque_integers_never_dereferenced(self):
        self.run_case("opaque_identity")


if __name__ == "__main__":
    unittest.main()
