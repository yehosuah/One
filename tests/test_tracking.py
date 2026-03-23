from datetime import date, datetime, time
import unittest

from one.models import CompletionState, Habit, ItemType, Todo, TodoStatus
from one.tracking import (
    build_today_items,
    materialize_habit_logs,
    set_habit_completion,
    todo_action_date,
    today_completion_ratio,
)


class TrackingTests(unittest.TestCase):
    def test_materialize_habit_logs_defaults_to_not_completed(self) -> None:
        target = date(2026, 3, 11)
        habit = Habit(
            id="h1",
            user_id="u1",
            category_id="c-gym",
            title="Workout",
            recurrence_rule="WEEKLY:MON,WED,FRI",
            start_date=date(2026, 1, 1),
        )

        logs = materialize_habit_logs(
            user_id="u1",
            habits=[habit],
            target_date=target,
            existing_logs=[],
        )

        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].item_type, ItemType.HABIT)
        self.assertEqual(logs[0].state, CompletionState.NOT_COMPLETED)

    def test_today_ordering_respects_locked_priority_buckets(self) -> None:
        target = date(2026, 3, 11)
        habit = Habit(
            id="h1",
            user_id="u1",
            category_id="c-gym",
            title="Gym Session",
            recurrence_rule="DAILY",
            start_date=date(2026, 1, 1),
            priority_weight=60,
            preferred_time=time(7, 0),
        )
        pinned = Todo(
            id="t1",
            user_id="u1",
            category_id="c-school",
            title="Pinned Project",
            is_pinned=True,
            due_at=datetime(2026, 3, 12, 12, 0),
        )
        urgent = Todo(
            id="t2",
            user_id="u1",
            category_id="c-school",
            title="Submit Assignment",
            due_at=datetime(2026, 3, 11, 9, 0),
            priority=80,
        )
        later = Todo(
            id="t3",
            user_id="u1",
            category_id="c-life",
            title="Buy Groceries",
            priority=40,
        )

        items = build_today_items(
            today=target,
            timezone="America/Guatemala",
            habits=[habit],
            todos=[later, urgent, pinned],
            completion_logs=[],
        )

        self.assertEqual([i.item_id for i in items], ["t1", "t2", "h1", "t3"])

    def test_habit_completion_updates_today_ratio(self) -> None:
        target = date(2026, 3, 11)
        habit = Habit(
            id="h1",
            user_id="u1",
            category_id="c-gym",
            title="Workout",
            recurrence_rule="DAILY",
            start_date=date(2026, 1, 1),
        )
        logs = materialize_habit_logs(
            user_id="u1",
            habits=[habit],
            target_date=target,
            existing_logs=[],
        )

        set_habit_completion(
            logs=logs,
            user_id="u1",
            habit_id="h1",
            target_date=target,
            completed=True,
        )

        items = build_today_items(
            today=target,
            timezone="America/Guatemala",
            habits=[habit],
            todos=[],
            completion_logs=logs,
        )
        self.assertTrue(items[0].completed)
        self.assertEqual(today_completion_ratio(items), 1.0)

    def test_completed_todo_stays_visible_in_today_execution(self) -> None:
        target = date(2026, 3, 11)
        todo = Todo(
            id="t1",
            user_id="u1",
            category_id="c-life",
            title="Buy groceries",
            priority=55,
            status=TodoStatus.COMPLETED,
            completed_at=datetime(2026, 3, 11, 19, 30),
            created_at=datetime(2026, 3, 11, 12, 0),
        )

        items = build_today_items(
            today=target,
            timezone="America/Guatemala",
            habits=[],
            todos=[todo],
            completion_logs=[],
        )

        self.assertEqual(len(items), 1)
        self.assertTrue(items[0].completed)
        self.assertEqual(items[0].item_type, ItemType.TODO)
        self.assertIn("completed", items[0].subtitle or "")

    def test_same_priority_remaining_todos_show_newest_first(self) -> None:
        target = date(2026, 3, 11)
        older = Todo(
            id="t-old",
            user_id="u1",
            category_id="c-life",
            title="Alpha task",
            priority=50,
            created_at=datetime(2026, 3, 10, 9, 0),
            updated_at=datetime(2026, 3, 10, 9, 0),
        )
        newer = Todo(
            id="t-new",
            user_id="u1",
            category_id="c-life",
            title="Zulu task",
            priority=50,
            created_at=datetime(2026, 3, 10, 10, 0),
            updated_at=datetime(2026, 3, 10, 10, 0),
        )

        items = build_today_items(
            today=target,
            timezone="America/Guatemala",
            habits=[],
            todos=[older, newer],
            completion_logs=[],
        )

        self.assertEqual([item.item_id for item in items], ["t-new", "t-old"])

    def test_todo_action_date_uses_due_date_else_created_date(self) -> None:
        todo_due = Todo(
            id="t1",
            user_id="u1",
            category_id="c1",
            title="With due date",
            due_at=datetime(2026, 3, 14, 5, 0),
            created_at=datetime(2026, 3, 10, 12, 0),
        )
        todo_no_due = Todo(
            id="t2",
            user_id="u1",
            category_id="c1",
            title="No due date",
            created_at=datetime(2026, 3, 10, 12, 0),
        )

        self.assertEqual(todo_action_date(todo_due, "America/Guatemala"), date(2026, 3, 13))
        self.assertEqual(todo_action_date(todo_no_due, "America/Guatemala"), date(2026, 3, 10))


if __name__ == "__main__":
    unittest.main()
