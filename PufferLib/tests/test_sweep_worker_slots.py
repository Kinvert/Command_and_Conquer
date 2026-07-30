import unittest

from pufferlib.pufferl import (
    _sweep_report_result,
    _sweep_should_collect,
    _sweep_should_suggest,
    _sweep_optimizer_config,
    _sweep_result_slot,
    _sweep_worker_layout,
)


class SweepWorkerSlotTest(unittest.TestCase):
    def test_worker_layout_repeats_each_physical_gpu_group_deterministically(self):
        self.assertEqual(_sweep_worker_layout(1, 1, 3), [(0,), (0,), (0,)])
        self.assertEqual(_sweep_worker_layout(2, 1, 3), [
            (0,), (1,), (0,), (1,), (0,), (1,),
        ])
        self.assertEqual(_sweep_worker_layout(4, 2, 2), [
            (0, 1), (2, 3), (0, 1), (2, 3),
        ])

    def test_worker_layout_rejects_invalid_gpu_shapes(self):
        invalid = [(0, 1, 1), (1, 0, 1), (1, 1, 0), (3, 2, 1)]
        for shape in invalid:
            with self.subTest(shape=shape), self.assertRaises(ValueError):
                _sweep_worker_layout(*shape)

    def test_result_slot_is_distinct_from_physical_gpu_with_legacy_fallback(self):
        self.assertEqual(_sweep_result_slot({"sweep_slot_id": 7, "gpu_id": 0}), 7)
        self.assertEqual(_sweep_result_slot({"gpu_id": 3}), 3)

    def test_workers_per_gpu_is_scheduler_config_not_optimizer_input(self):
        method, optimizer = _sweep_optimizer_config({
            "method": "Protein",
            "workers_per_gpu": 3,
            "train": {
                "learning_rate": {
                    "distribution": "uniform",
                    "min": 0.001,
                    "max": 0.01,
                    "scale": "auto",
                },
            },
        })
        self.assertEqual(method, "Protein")
        self.assertNotIn("workers_per_gpu", optimizer)
        self.assertIn("train", optimizer)

    def test_final_concurrent_batch_is_drained_before_scheduler_exit(self):
        self.assertTrue(_sweep_should_collect(3, 0, 3, 3))
        self.assertTrue(_sweep_should_collect(2, 1, 3, 3))
        self.assertTrue(_sweep_should_collect(1, 2, 3, 3))
        self.assertFalse(_sweep_should_collect(0, 3, 3, 3))

        # A failed run does not count as completed, so its open slot is replaced.
        self.assertFalse(_sweep_should_collect(2, 0, 3, 3))

    def test_only_first_experiment_uses_default_hyperparameters(self):
        self.assertFalse(_sweep_should_suggest(0))
        self.assertTrue(_sweep_should_suggest(1))
        self.assertTrue(_sweep_should_suggest(2))

    def test_only_rank_zero_reports_a_multi_gpu_trial_result(self):
        class Queue:
            def __init__(self):
                self.items = []

            def put(self, item):
                self.items.append(item)

        queue = Queue()
        payload = ([0.5], [1.0], [1024])
        _sweep_report_result(queue, {"rank": 1, "sweep_slot_id": 7, "gpu_id": 1}, *payload)
        self.assertEqual(queue.items, [])

        _sweep_report_result(queue, {"rank": 0, "sweep_slot_id": 7, "gpu_id": 0}, *payload)
        self.assertEqual(queue.items, [(7, *payload)])


if __name__ == "__main__":
    unittest.main()
