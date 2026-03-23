from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, time
from uuid import uuid4
from zoneinfo import ZoneInfo

from .models import CompletionLog, CompletionState, Habit, ItemType, Todo, TodoStatus

_WEEKDAY_INDEX = {
    "MON": 0,
    "TUE": 1,
    "WED": 2,
    "THU": 3,
    "FRI": 4,
    "SAT": 5,
    "SUN": 6,
}


@dataclass(slots=True)
class TodayItem:
    item_type: ItemType
    item_id: str
    title: str
    category_id: str
    completed: bool
    sort_bucket: int
    sort_score: float
    subtitle: str | None = None
    is_pinned: bool | None = None
    priority: int | None = None
    due_at: datetime | None = None
    preferred_time: time | None = None


def _as_local(dt: datetime, timezone: str) -> datetime:
    tz = ZoneInfo(timezone)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return dt.astimezone(tz)


def todo_action_date(todo: Todo, timezone: str) -> date:
    if todo.due_at is not None:
        return _as_local(todo.due_at, timezone).date()
    return _as_local(todo.created_at, timezone).date()


def is_habit_scheduled(habit: Habit, target_date: date) -> bool:
    if not habit.is_active:
        return False
    if target_date < habit.start_date:
        return False
    if habit.end_date is not None and target_date > habit.end_date:
        return False

    rule = habit.recurrence_rule.strip().upper()
    if not rule or rule == "DAILY":
        return True

    if rule.startswith("WEEKLY:"):
        day_codes = [x.strip() for x in rule.split(":", 1)[1].split(",") if x.strip()]
        valid_days = {_WEEKDAY_INDEX[d] for d in day_codes if d in _WEEKDAY_INDEX}
        return target_date.weekday() in valid_days

    if rule.startswith("MONTHLY:"):
        days = [x.strip() for x in rule.split(":", 1)[1].split(",") if x.strip()]
        valid_days = {int(d) for d in days if d.isdigit()}
        return target_date.day in valid_days

    if rule.startswith("YEARLY:"):
        month_days = [x.strip() for x in rule.split(":", 1)[1].split(",") if x.strip()]
        current = f"{target_date.month:02d}-{target_date.day:02d}"
        return current in month_days

    return False


def materialize_habit_logs(
    *,
    user_id: str,
    habits: list[Habit],
    target_date: date,
    existing_logs: list[CompletionLog],
    source: str = "materializer",
) -> list[CompletionLog]:
    existing_keys = {
        (log.item_type, log.item_id, log.date_local)
        for log in existing_logs
        if log.item_type is ItemType.HABIT
    }
    created: list[CompletionLog] = []

    for habit in habits:
        if habit.user_id != user_id:
            continue
        if not is_habit_scheduled(habit, target_date):
            continue
        key = (ItemType.HABIT, habit.id, target_date)
        if key in existing_keys:
            continue

        created.append(
            CompletionLog(
                id=str(uuid4()),
                user_id=user_id,
                item_type=ItemType.HABIT,
                item_id=habit.id,
                date_local=target_date,
                state=CompletionState.NOT_COMPLETED,
                source=source,
            )
        )

    return created


def set_habit_completion(
    *,
    logs: list[CompletionLog],
    user_id: str,
    habit_id: str,
    target_date: date,
    completed: bool,
    source: str = "app",
    completed_at: datetime | None = None,
) -> CompletionLog:
    now = datetime.now(UTC)
    for log in logs:
        if (
            log.user_id == user_id
            and log.item_type is ItemType.HABIT
            and log.item_id == habit_id
            and log.date_local == target_date
        ):
            log.state = CompletionState.COMPLETED if completed else CompletionState.NOT_COMPLETED
            log.completed_at = completed_at or now if completed else None
            log.updated_at = now
            log.source = source
            return log

    new_log = CompletionLog(
        id=str(uuid4()),
        user_id=user_id,
        item_type=ItemType.HABIT,
        item_id=habit_id,
        date_local=target_date,
        state=CompletionState.COMPLETED if completed else CompletionState.NOT_COMPLETED,
        completed_at=completed_at or now if completed else None,
        source=source,
    )
    logs.append(new_log)
    return new_log


def set_todo_completion(todo: Todo, *, completed: bool, completed_at: datetime | None = None) -> Todo:
    now = datetime.now(UTC)
    if completed:
        todo.status = TodoStatus.COMPLETED
        todo.completed_at = completed_at or now
    else:
        todo.status = TodoStatus.OPEN
        todo.completed_at = None
    todo.updated_at = now
    return todo


def _todo_urgency_score(todo: Todo, today: date, timezone: str) -> float:
    score = float(todo.priority)
    if todo.due_at is None:
        return score

    due_date = _as_local(todo.due_at, timezone).date()
    delta = (due_date - today).days
    if delta < 0:
        score += 200 + abs(delta) * 10
    elif delta == 0:
        score += 150
    elif delta == 1:
        score += 100
    else:
        score += max(0, 40 - delta)
    return score


def _habit_sort_score(habit: Habit) -> float:
    score = float(habit.priority_weight)
    if habit.preferred_time is not None:
        minutes = habit.preferred_time.hour * 60 + habit.preferred_time.minute
        # Earlier preferred times are ranked slightly higher for morning planning.
        score += max(0, (24 * 60 - minutes) / 1440)
    return score


def _todo_today_sort_key(todo: Todo, today: date, timezone: str) -> tuple[float, float, str]:
    return (
        -_todo_urgency_score(todo, today, timezone),
        -todo.created_at.timestamp(),
        todo.title.casefold(),
    )


def _habit_today_sort_key(habit: Habit) -> tuple[float, str]:
    return (-_habit_sort_score(habit), habit.title.casefold())


def build_today_items(
    *,
    today: date,
    timezone: str,
    habits: list[Habit],
    todos: list[Todo],
    completion_logs: list[CompletionLog],
) -> list[TodayItem]:
    habit_logs = {
        log.item_id: log
        for log in completion_logs
        if log.item_type is ItemType.HABIT and log.date_local == today
    }

    items: list[TodayItem] = []

    pinned_todos = sorted(
        [todo for todo in todos if todo.status is TodoStatus.OPEN and todo.is_pinned],
        key=lambda todo: _todo_today_sort_key(todo, today, timezone),
    )
    urgent_todos = sorted(
        [
            todo
            for todo in todos
            if todo.status is TodoStatus.OPEN and not todo.is_pinned and todo.due_at is not None and _as_local(todo.due_at, timezone).date() <= today
        ],
        key=lambda todo: _todo_today_sort_key(todo, today, timezone),
    )
    remaining_todos = sorted(
        [
            todo
            for todo in todos
            if todo.status is TodoStatus.OPEN and not todo.is_pinned and todo not in urgent_todos
        ],
        key=lambda todo: _todo_today_sort_key(todo, today, timezone),
    )
    completed_todos = sorted(
        [
            todo
            for todo in todos
            if todo.status is TodoStatus.COMPLETED and todo_action_date(todo, timezone) == today
        ],
        key=lambda todo: _todo_today_sort_key(todo, today, timezone),
    )
    scheduled_habits = sorted(
        [habit for habit in habits if is_habit_scheduled(habit, today)],
        key=_habit_today_sort_key,
    )

    for todo in pinned_todos:
        subtitle = "Todo"
        if todo.due_at is not None:
            subtitle = f"{subtitle} · due {_as_local(todo.due_at, timezone).strftime('%H:%M')}"
        subtitle = f"{subtitle} · priority {todo.priority}"
        items.append(
            TodayItem(
                item_type=ItemType.TODO,
                item_id=todo.id,
                title=todo.title,
                category_id=todo.category_id,
                completed=False,
                sort_bucket=0,
                sort_score=_todo_urgency_score(todo, today, timezone),
                subtitle=subtitle,
                is_pinned=todo.is_pinned,
                priority=todo.priority,
                due_at=todo.due_at,
            )
        )

    for todo in urgent_todos:
        subtitle = "Todo"
        if todo.due_at is not None:
            subtitle = f"{subtitle} · due {_as_local(todo.due_at, timezone).strftime('%H:%M')}"
        subtitle = f"{subtitle} · priority {todo.priority}"
        items.append(
            TodayItem(
                item_type=ItemType.TODO,
                item_id=todo.id,
                title=todo.title,
                category_id=todo.category_id,
                completed=False,
                sort_bucket=1,
                sort_score=_todo_urgency_score(todo, today, timezone),
                subtitle=subtitle,
                is_pinned=todo.is_pinned,
                priority=todo.priority,
                due_at=todo.due_at,
            )
        )

    for habit in scheduled_habits:
        log = habit_logs.get(habit.id)
        subtitle = f"Habit · {habit.recurrence_rule}"
        if habit.preferred_time is not None:
            subtitle = f"{subtitle} · {habit.preferred_time.strftime('%H:%M')}"
        items.append(
            TodayItem(
                item_type=ItemType.HABIT,
                item_id=habit.id,
                title=habit.title,
                category_id=habit.category_id,
                completed=(log is not None and log.state is CompletionState.COMPLETED),
                sort_bucket=2,
                sort_score=_habit_sort_score(habit),
                subtitle=subtitle,
                is_pinned=False,
                priority=habit.priority_weight,
                preferred_time=habit.preferred_time,
            )
        )

    for todo in remaining_todos:
        subtitle = "Todo"
        if todo.due_at is not None:
            subtitle = f"{subtitle} · due {_as_local(todo.due_at, timezone).strftime('%H:%M')}"
        subtitle = f"{subtitle} · priority {todo.priority}"
        items.append(
            TodayItem(
                item_type=ItemType.TODO,
                item_id=todo.id,
                title=todo.title,
                category_id=todo.category_id,
                completed=False,
                sort_bucket=3,
                sort_score=_todo_urgency_score(todo, today, timezone),
                subtitle=subtitle,
                is_pinned=todo.is_pinned,
                priority=todo.priority,
                due_at=todo.due_at,
            )
        )

    for todo in completed_todos:
        subtitle = "Todo · completed"
        if todo.completed_at is not None:
            subtitle = f"{subtitle} · {_as_local(todo.completed_at, timezone).strftime('%H:%M')}"
        items.append(
            TodayItem(
                item_type=ItemType.TODO,
                item_id=todo.id,
                title=todo.title,
                category_id=todo.category_id,
                completed=True,
                sort_bucket=4,
                sort_score=_todo_urgency_score(todo, today, timezone),
                subtitle=subtitle,
                is_pinned=todo.is_pinned,
                priority=todo.priority,
                due_at=todo.due_at,
            )
        )

    items.sort(key=lambda x: (x.sort_bucket, -x.sort_score))
    return items


def today_completion_ratio(items: list[TodayItem]) -> float:
    if not items:
        return 0.0
    completed = sum(1 for item in items if item.completed)
    return completed / len(items)
