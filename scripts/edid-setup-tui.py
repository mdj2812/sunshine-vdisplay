#!/usr/bin/env python3
"""Hermes-style interactive EDID mode picker for install.sh.

Uses curses arrow-key menus when available, with a numbered fallback.
Prints JSON to stdout: {"primary": "...", "extra": ["...", ...]}
"""
from __future__ import annotations

import argparse
import curses
import json
import sys
from typing import Callable, Iterable, Sequence

MAX_EXTRAS = 5

# (width, height, aspect label, supported refresh rates)
RESOLUTIONS = (
    (2560, 1440, "16:9", (144, 120, 60)),
    (2560, 1600, "16:10", (144, 120, 60)),
    (1920, 1080, "16:9", (144, 120, 60)),
    (1920, 1200, "16:10", (120, 60)),
    (3840, 2160, "16:9 4K", (60,)),
    (1600, 1200, "4:3", (120, 60)),
    (1280, 960, "4:3", (120, 60)),
    (1280, 1024, "5:4", (120, 60)),
)


def build_mode(width: int, height: int, refresh: int) -> str:
    return f"{width}x{height}@{refresh}"


def all_catalog_modes() -> list[str]:
    modes: list[str] = []
    for width, height, _aspect, refresh_rates in RESOLUTIONS:
        for refresh in refresh_rates:
            modes.append(build_mode(width, height, refresh))
    return modes


def build_mode_labels() -> dict[str, str]:
    labels: dict[str, str] = {}
    for width, height, aspect, refresh_rates in RESOLUTIONS:
        for refresh in refresh_rates:
            mode = build_mode(width, height, refresh)
            suffix = ", default" if mode == "2560x1440@120" else ""
            labels[mode] = f"{mode}  ({aspect}{suffix})"
    return labels


MODE_LABELS = build_mode_labels()

PRIMARY_PRESETS = [
    build_mode(2560, 1440, 144),
    build_mode(2560, 1440, 120),
    build_mode(2560, 1440, 60),
    build_mode(2560, 1600, 144),
    build_mode(2560, 1600, 120),
    build_mode(2560, 1600, 60),
    build_mode(1920, 1080, 144),
    build_mode(1920, 1080, 120),
    build_mode(1920, 1080, 60),
    build_mode(3840, 2160, 60),
]

EXTRA_CATALOG = all_catalog_modes()

DEFAULT_EXTRAS = [
    build_mode(2560, 1440, 60),
    build_mode(2560, 1600, 120),
    build_mode(2560, 1600, 60),
    build_mode(1920, 1080, 120),
    build_mode(1920, 1080, 60),
]


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def label(mode: str) -> str:
    return MODE_LABELS.get(mode, mode)


def default_extras(primary: str) -> list[str]:
    return [mode for mode in DEFAULT_EXTRAS if mode != primary]


def parse_mode_list(text: str) -> list[str]:
    return [item.strip() for item in text.split(",") if item.strip()]


def attach_tty() -> None:
    if sys.stdin.isatty():
        return
    try:
        sys.stdin = open("/dev/tty", "r")  # noqa: SIM115
    except OSError:
        pass


def flush_stdin() -> None:
    try:
        import termios

        termios.tcflush(sys.stdin, termios.TCIFLUSH)
    except Exception:
        pass


def print_banner() -> None:
    cyan = "\033[0;36m"
    bold = "\033[1m"
    reset = "\033[0m"
    eprint(f"{cyan}{bold}")
    eprint("┌─────────────────────────────────────────────────────────┐")
    eprint("│  Sunshine Virtual Display — EDID Setup                  │")
    eprint("├─────────────────────────────────────────────────────────┤")
    eprint("│  Pick primary mode and optional extra EDID timings      │")
    eprint("└─────────────────────────────────────────────────────────┘")
    eprint(reset)


def prompt_line(question: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    try:
        value = input(f"{question}{suffix}: ").strip()
    except (EOFError, KeyboardInterrupt):
        raise SystemExit(1) from None
    return value or default


def _addnstr(win, y: int, x: int, text: str, width: int, attr: int = 0) -> None:
    try:
        win.addnstr(y, x, text, max(0, width), attr)
    except curses.error:
        pass


def _init_colors() -> None:
    if not curses.has_colors():
        return
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)
    curses.init_pair(2, curses.COLOR_YELLOW, -1)


def _cursor_attr(is_cursor: bool) -> int:
    if not is_cursor:
        return curses.A_NORMAL
    attr = curses.A_BOLD
    if curses.has_colors():
        attr |= curses.color_pair(1)
    return attr


def _title_attr() -> int:
    attr = curses.A_BOLD
    if curses.has_colors():
        attr |= curses.color_pair(2)
    return attr


def _run_menu(
    title: str,
    hint: str,
    item_count: int,
    draw_row: Callable,
    on_key: Callable[[int, int], object | None],
    initial_cursor: int = 0,
    footer: Callable | None = None,
) -> object | None:
    def _draw(stdscr):
        curses.curs_set(0)
        _init_colors()
        cursor = initial_cursor
        scroll = 0

        while True:
            stdscr.clear()
            height, width = stdscr.getmaxyx()
            reserve = 2 if footer else 1
            _addnstr(stdscr, 0, 0, title, width - 1, _title_attr())
            _addnstr(stdscr, 1, 0, hint, width - 1, curses.A_DIM)
            visible = max(1, height - 3 - reserve)
            if cursor < scroll:
                scroll = cursor
            elif cursor >= scroll + visible:
                scroll = cursor - visible + 1
            row_y = 3
            for index in range(scroll, min(item_count, scroll + visible)):
                draw_row(stdscr, row_y, index, index == cursor, width)
                row_y += 1
            if footer is not None:
                footer(stdscr, height, width, cursor)
            stdscr.refresh()

            key = stdscr.getch()
            if key in (curses.KEY_UP, ord("k")):
                cursor = (cursor - 1) % item_count
                continue
            if key in (curses.KEY_DOWN, ord("j")):
                cursor = (cursor + 1) % item_count
                continue

            result = on_key(key, cursor)
            if result is not None:
                return result

    return curses.wrapper(_draw)


def curses_radiolist(title: str, items: Sequence[str], selected: int) -> int:
    def draw_row(stdscr, y: int, index: int, is_cursor: bool, width: int) -> None:
        radio = "●" if is_cursor else "○"
        arrow = "→" if is_cursor else " "
        line = f" {arrow} ({radio}) {items[index]}"
        _addnstr(stdscr, y, 0, line, width - 1, _cursor_attr(is_cursor))

    def on_key(key: int, cursor: int) -> int | None:
        if key in (curses.KEY_ENTER, 10, 13, ord(" ")):
            return cursor
        if key in (27, ord("q")):
            return selected
        return None

    result = _run_menu(
        title,
        "↑/↓ navigate · Enter/Space select · Esc keep default",
        len(items),
        draw_row,
        on_key,
        initial_cursor=selected,
    )
    return selected if result is None else int(result)


def curses_checklist(
    title: str,
    items: Sequence[str],
    selected: set[int],
    max_selected: int,
) -> set[int]:
    chosen = set(selected)

    def draw_row(stdscr, y: int, index: int, is_cursor: bool, width: int) -> None:
        mark = "✓" if index in chosen else " "
        arrow = "→" if is_cursor else " "
        line = f" {arrow} [{mark}] {items[index]}"
        _addnstr(stdscr, y, 0, line, width - 1, _cursor_attr(is_cursor))

    def footer(stdscr, height: int, width: int, _cursor: int) -> None:
        text = f"Selected {len(chosen)}/{max_selected}"
        _addnstr(stdscr, height - 1, max(0, width - len(text) - 1), text, len(text), curses.A_DIM)

    def on_key(key: int, cursor: int) -> set[int] | None:
        if key == ord(" "):
            if cursor in chosen:
                chosen.discard(cursor)
            elif len(chosen) < max_selected:
                chosen.add(cursor)
            return None
        if key in (curses.KEY_ENTER, 10, 13):
            return set(chosen)
        if key in (27, ord("q")):
            return set(selected)
        return None

    result = _run_menu(
        title,
        "↑/↓ navigate · Space toggle · Enter confirm · Esc keep defaults",
        len(items),
        draw_row,
        on_key,
        initial_cursor=0,
        footer=footer,
    )
    return selected if result is None else set(result)


def numbered_radiolist(title: str, items: Sequence[str], selected: int) -> int:
    eprint()
    eprint(title)
    for index, item in enumerate(items):
        marker = "●" if index == selected else "○"
        eprint(f"  {index + 1}) {marker} {item}")
    while True:
        value = prompt_line("Choice", str(selected + 1))
        if value.isdigit() and 1 <= int(value) <= len(items):
            return int(value) - 1
        eprint("Enter a number from the list.")


def numbered_checklist(
    title: str,
    items: Sequence[str],
    selected: set[int],
    max_selected: int,
) -> set[int]:
    chosen = set(selected)
    eprint()
    eprint(title)
    eprint(f"Toggle numbers (max {max_selected}), Enter when done.")

    while True:
        for index, item in enumerate(items):
            mark = "x" if index in chosen else " "
            eprint(f"  {index + 1}) [{mark}] {item}")
        value = prompt_line("Toggle / Enter", "")
        if not value:
            return chosen
        for token in value.split():
            if not token.isdigit():
                continue
            index = int(token) - 1
            if index < 0 or index >= len(items):
                continue
            if index in chosen:
                chosen.discard(index)
            elif len(chosen) < max_selected:
                chosen.add(index)
        eprint()


def pick_primary(default_primary: str) -> str:
    labels = [label(mode) for mode in PRIMARY_PRESETS] + ["Custom mode (WIDTHxHEIGHT@HZ)"]
    default_index = PRIMARY_PRESETS.index(default_primary) if default_primary in PRIMARY_PRESETS else 0

    try:
        if sys.stdin.isatty():
            index = curses_radiolist("Primary virtual display mode (EDID preferred timing)", labels, default_index)
        else:
            raise curses.error
    except (curses.error, ImportError):
        index = numbered_radiolist("Primary virtual display mode (EDID preferred timing)", labels, default_index)

    if index == len(PRIMARY_PRESETS):
        flush_stdin()
        custom = prompt_line("Custom mode", default_primary)
        if not custom:
            eprint("error: custom mode cannot be empty")
            raise SystemExit(1)
        return custom
    return PRIMARY_PRESETS[index]


def pick_extras(primary: str, default_extra: Iterable[str]) -> list[str]:
    available = [mode for mode in EXTRA_CATALOG if mode != primary]
    labels = [label(mode) for mode in available]
    preselected = {
        index
        for index, mode in enumerate(available)
        if mode in set(default_extra)
    }

    try:
        if sys.stdin.isatty():
            chosen = curses_checklist(
                f"Additional EDID modes (up to {MAX_EXTRAS}; primary is {primary})",
                labels,
                preselected,
                MAX_EXTRAS,
            )
        else:
            raise curses.error
    except (curses.error, ImportError):
        chosen = numbered_checklist(
            f"Additional EDID modes (up to {MAX_EXTRAS}; primary is {primary})",
            labels,
            preselected,
            MAX_EXTRAS,
        )

    return [available[index] for index in sorted(chosen)]


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--default-primary", default="2560x1440@120")
    parser.add_argument("--default-extra", default="")
    parser.add_argument("--skip-extra", action="store_true")
    parser.add_argument(
        "--output",
        help="Write JSON result to a file (stdout stays free for the TUI)",
    )
    return parser.parse_args(argv)


def write_result(payload: dict, output: str | None) -> None:
    text = json.dumps(payload)
    if output:
        with open(output, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.write("\n")
        return
    print(text)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    attach_tty()
    print_banner()

    primary = pick_primary(args.default_primary)
    if args.skip_extra:
        extra = parse_mode_list(args.default_extra)
    else:
        defaults = parse_mode_list(args.default_extra) or default_extras(primary)
        extra = pick_extras(primary, defaults)

    write_result({"primary": primary, "extra": extra}, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
