#!/usr/bin/env python3
import os
import shutil
import threading
import glob
from dataclasses import dataclass
from pathlib import Path
import tkinter as tk
from tkinter import messagebox


@dataclass(frozen=True)
class CacheTarget:
    key: str
    label: str
    path: Path
    enabled_by_default: bool = True


HOME = Path.home()
CACHE_TARGETS = [
    CacheTarget("user_cache", "User cache (~Library/Caches)", HOME / "Library/Caches"),
    CacheTarget("logs", "User logs (~Library/Logs)", HOME / "Library/Logs", False),
    CacheTarget("xcode_derived", "Xcode DerivedData", HOME / "Library/Developer/Xcode/DerivedData"),
    CacheTarget("xcode_archives", "Xcode Archives", HOME / "Library/Developer/Xcode/Archives", False),
    CacheTarget("xcode_device_support", "Xcode iOS DeviceSupport", HOME / "Library/Developer/Xcode/iOS DeviceSupport", False),
    CacheTarget("android_studio", "Android Studio caches", HOME / "Library/Caches/Google/AndroidStudio*"),
    CacheTarget("gradle", "Gradle caches (~/.gradle/caches)", HOME / ".gradle/caches"),
    CacheTarget("npm", "npm cache (~/.npm)", HOME / ".npm", False),
    CacheTarget("yarn", "Yarn cache (~/.yarn)", HOME / ".yarn", False),
    CacheTarget("cocoapods", "CocoaPods cache (~/.cocoapods)", HOME / ".cocoapods", False),
]


def format_size(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size_bytes)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{size_bytes} B"


def size_of_path(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size

    total = 0
    for root, _, files in os.walk(path, topdown=True):
        for name in files:
            file_path = Path(root) / name
            try:
                total += file_path.stat().st_size
            except (FileNotFoundError, PermissionError, OSError):
                continue
    return total


def resolve_paths(target_path: Path) -> list[Path]:
    as_text = str(target_path)
    if "*" in as_text:
        return [Path(p) for p in sorted(glob.glob(as_text))]
    return [target_path]


def clear_folder_contents(folder: Path) -> tuple[int, int]:
    deleted_items = 0
    freed_bytes = 0
    if not folder.exists():
        return deleted_items, freed_bytes

    for child in folder.iterdir():
        try:
            child_size = size_of_path(child)
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink(missing_ok=True)
            deleted_items += 1
            freed_bytes += child_size
        except (PermissionError, OSError):
            continue

    return deleted_items, freed_bytes


class CacheCleanerApp(tk.Tk):
    BG_MAIN = "#151a21"
    BG_PANEL = "#1f2630"
    BG_CARD = "#28313b"
    FG_MAIN = "#eef2f7"
    FG_MUTED = "#9aa8ba"
    ACCENT = "#4f8cff"
    SUCCESS = "#44b273"
    DANGER = "#d85b63"
    CARD_HL = "#364150"

    def __init__(self) -> None:
        super().__init__()
        self.title("Mac Cache Cleaner")
        self.geometry("900x640")
        self.minsize(820, 560)
        self.configure(bg=self.BG_MAIN)

        self.vars: dict[str, tk.BooleanVar] = {}
        self.size_labels: dict[str, tk.Label] = {}
        self.path_labels: dict[str, tk.Label] = {}
        self.storage_labels: dict[str, tk.Label] = {}
        self.total_cache_bytes = 0

        self._build_ui()
        self.scan_sizes()

    def _make_button(
        self,
        parent: tk.Widget,
        text: str,
        command: object,
        bg: str = "#344152",
        fg: str = "#f7f9fc",
    ) -> tk.Button:
        return tk.Button(
            parent,
            text=text,
            command=command,
            bg=bg,
            fg=fg,
            activebackground=bg,
            activeforeground=fg,
            relief=tk.FLAT,
            bd=0,
            padx=12,
            pady=8,
            cursor="hand2",
            font=("SF Pro Text", 12),
        )

    def _build_ui(self) -> None:
        frame = tk.Frame(self, bg=self.BG_MAIN, padx=18, pady=18)
        frame.pack(fill=tk.BOTH, expand=True)

        header = tk.Frame(frame, bg=self.BG_PANEL, padx=16, pady=16, highlightbackground=self.CARD_HL, highlightthickness=1)
        header.pack(fill=tk.X, pady=(0, 12))

        title = tk.Label(header, text="Mac Cache Cleaner", font=("SF Pro Display", 24, "bold"), bg=self.BG_PANEL, fg=self.FG_MAIN)
        title.pack(anchor=tk.W)

        subtitle = tk.Label(
            header,
            text="Clean system and developer caches, including Xcode and Android Studio targets.",
            bg=self.BG_PANEL,
            fg=self.FG_MUTED,
            font=("SF Pro Text", 12),
        )
        subtitle.pack(anchor=tk.W, pady=(3, 0))

        stats_row = tk.Frame(frame, bg=self.BG_MAIN)
        stats_row.pack(fill=tk.X, pady=(0, 12))

        for key, title, value, color in [
            ("total", "Total Disk", "--", self.ACCENT),
            ("used", "Used", "--", self.DANGER),
            ("free", "Free", "--", self.SUCCESS),
            ("cache", "Cache Footprint", "--", "#8065ff"),
        ]:
            card = tk.Frame(stats_row, bg=self.BG_PANEL, padx=12, pady=10, highlightbackground=self.CARD_HL, highlightthickness=1)
            card.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
            if key == "cache":
                card.pack_configure(padx=(0, 0))
            tk.Label(card, text=title, bg=self.BG_PANEL, fg=self.FG_MUTED, font=("SF Pro Text", 10)).pack(anchor=tk.W)
            val_label = tk.Label(card, text=value, bg=self.BG_PANEL, fg=color, font=("SF Pro Display", 17, "bold"))
            val_label.pack(anchor=tk.W, pady=(2, 0))
            self.storage_labels[key] = val_label

        controls = tk.Frame(frame, bg=self.BG_MAIN)
        controls.pack(fill=tk.X, pady=(0, 10))
        self._make_button(controls, "Scan Sizes", self.scan_sizes, bg=self.ACCENT).pack(side=tk.LEFT)
        self._make_button(controls, "Select All", self.select_all).pack(side=tk.LEFT, padx=(8, 0))
        self._make_button(controls, "Select Recommended", self.select_recommended).pack(side=tk.LEFT, padx=(8, 0))
        self._make_button(controls, "Clear Selected", self.clear_selected, bg=self.DANGER).pack(side=tk.RIGHT)

        list_container = tk.Frame(frame, bg=self.BG_PANEL, padx=8, pady=8)
        list_container.pack(fill=tk.BOTH, expand=True)

        canvas = tk.Canvas(list_container, highlightthickness=0, bg=self.BG_PANEL)
        scrollbar = tk.Scrollbar(list_container, orient=tk.VERTICAL, command=canvas.yview)
        scroll_frame = tk.Frame(canvas, bg=self.BG_PANEL)

        scroll_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all")),
        )
        canvas.create_window((0, 0), window=scroll_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        def _on_mousewheel(event: tk.Event) -> None:
            canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")

        canvas.bind_all("<MouseWheel>", _on_mousewheel)

        for target in CACHE_TARGETS:
            row = tk.Frame(scroll_frame, bg=self.BG_CARD, padx=12, pady=10, highlightbackground=self.CARD_HL, highlightthickness=1)
            row.pack(fill=tk.X, pady=(0, 8))

            var = tk.BooleanVar(value=target.enabled_by_default)
            self.vars[target.key] = var
            tk.Checkbutton(
                row,
                variable=var,
                text=target.label,
                bg=self.BG_CARD,
                fg=self.FG_MAIN,
                selectcolor="#3c4a5d",
                activebackground=self.BG_CARD,
                activeforeground=self.FG_MAIN,
                font=("SF Pro Text", 12, "bold"),
            ).pack(side=tk.LEFT, anchor=tk.W)

            size_label = tk.Label(
                row,
                text="Not scanned",
                bg="#3a4758",
                fg="#f8fafc",
                padx=10,
                pady=4,
                font=("SF Pro Text", 11, "bold"),
            )
            size_label.pack(side=tk.RIGHT)
            self.size_labels[target.key] = size_label

            path_label = tk.Label(
                row,
                text=str(target.path),
                bg=self.BG_CARD,
                fg=self.FG_MUTED,
                anchor="w",
                justify=tk.LEFT,
                font=("SF Mono", 10),
            )
            path_label.pack(fill=tk.X, padx=(22, 0), pady=(2, 0))
            self.path_labels[target.key] = path_label

        footer = tk.Frame(frame, bg=self.BG_MAIN)
        footer.pack(fill=tk.X, pady=(10, 0))
        self.status = tk.Label(
            footer,
            text="Ready. Start with Scan Sizes.",
            bg=self.BG_MAIN,
            fg=self.FG_MAIN,
            font=("SF Pro Text", 11),
        )
        self.status.pack(side=tk.LEFT)

        hint = tk.Label(
            footer,
            text="Tip: Close IDEs before cleaning for best results.",
            bg=self.BG_MAIN,
            fg=self.FG_MUTED,
            font=("SF Pro Text", 10),
        )
        hint.pack(side=tk.RIGHT)

    def select_all(self) -> None:
        for var in self.vars.values():
            var.set(True)
        self.status.config(text="All targets selected.")

    def select_recommended(self) -> None:
        for target in CACHE_TARGETS:
            self.vars[target.key].set(target.enabled_by_default)
        self.status.config(text="Recommended targets selected.")

    def scan_sizes(self) -> None:
        self.status.config(text="Scanning cache sizes...")
        for label in self.size_labels.values():
            label.config(text="Scanning...")

        threading.Thread(target=self._scan_sizes_worker, daemon=True).start()

    def _scan_sizes_worker(self) -> None:
        target_sizes: dict[str, int] = {}
        total_cache = 0
        for target in CACHE_TARGETS:
            resolved = resolve_paths(target.path)
            size = sum(size_of_path(path) for path in resolved)
            target_sizes[target.key] = size
            total_cache += size

        disk = shutil.disk_usage(HOME)
        self.after(0, lambda: self._update_sizes_ui(target_sizes, total_cache, disk))

    def _update_sizes_ui(self, target_sizes: dict[str, int], total_cache: int, disk: tuple[int, int, int]) -> None:
        for target in CACHE_TARGETS:
            self.size_labels[target.key].config(text=format_size(target_sizes[target.key]))
        self.total_cache_bytes = total_cache
        self.storage_labels["total"].config(text=format_size(disk.total))
        self.storage_labels["used"].config(text=format_size(disk.used))
        self.storage_labels["free"].config(text=format_size(disk.free))
        self.storage_labels["cache"].config(text=format_size(total_cache))
        self.status.config(text=f"Scan complete. Cache footprint: {format_size(total_cache)}")

    def clear_selected(self) -> None:
        selected = [t for t in CACHE_TARGETS if self.vars[t.key].get()]
        if not selected:
            messagebox.showinfo("No selection", "Select at least one cache target.")
            return

        details = "\n".join([f"- {target.label}" for target in selected])
        confirmed = messagebox.askyesno(
            "Confirm Cache Cleanup",
            f"Delete contents for these cache targets?\n\n{details}\n\nThis cannot be undone.",
        )
        if not confirmed:
            return

        self.status.config(text="Cleaning selected cache targets...")
        threading.Thread(target=self._clear_worker, args=(selected,), daemon=True).start()

    def _clear_worker(self, selected: list[CacheTarget]) -> None:
        total_items = 0
        total_freed = 0
        for target in selected:
            resolved = resolve_paths(target.path)
            for path in resolved:
                items, freed = clear_folder_contents(path)
                total_items += items
                total_freed += freed

        self.after(0, lambda: self._cleanup_finished(total_items, total_freed))

    def _cleanup_finished(self, total_items: int, total_freed: int) -> None:
        self.status.config(
            text=f"Cleanup complete. Removed {total_items} items, freed about {format_size(total_freed)}."
        )
        self.scan_sizes()


if __name__ == "__main__":
    app = CacheCleanerApp()
    app.mainloop()
