"""
Renders the dbt lineage graph to a PNG image.

Reads `target/manifest.json` (produced by any `dbt parse` / `dbt build` run),
so the picture always reflects the real `ref()` dependencies rather than a
hand-maintained drawing.

Models are laid out in columns by layer (raw -> staging -> core -> finops) and
coloured by materialisation, so the incremental models stand out.

Usage:
    dbt parse                                   # refresh the manifest first
    python scripts/render_lineage.py            # writes docs/lineage.png
"""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no GUI needed - we only write a file

import matplotlib.patches as mpatches
import networkx as nx
from matplotlib import pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "target" / "manifest.json"
OUTPUT_DIR = ROOT / "docs"
OUTPUT_PNG = OUTPUT_DIR / "lineage.png"
OUTPUT_SVG = OUTPUT_DIR / "lineage.svg"

# Column position for each layer, left to right.
LAYER_ORDER = ["raw", "staging", "core", "finops"]
LAYER_TITLES = {
    "raw": "RAW\nland the JSON",
    "staging": "STAGING\nflatten the nesting",
    "core": "MARTS · CORE\nbusiness entities",
    "finops": "MARTS · FINOPS\nspend analytics",
}

# Fill colour per materialisation.
COLOURS = {
    "view": "#DCEBFA",
    "table": "#D6EFD8",
    "incremental": "#FBE3C2",
}
EDGE_COLOURS = {
    "view": "#4A87BD",
    "table": "#4F9A5B",
    "incremental": "#D98723",
}

BOX_W = 2.55
BOX_H = 0.52
X_GAP = 4.3
Y_GAP = 0.86


def layer_of(node: dict) -> str | None:
    """Map a model's file path to one of the four layers.

    Note we use `original_file_path`, not `path`. Because each layer is its own
    entry in `model-paths`, `path` is relative to that root and so is just the
    bare filename - the layer name is only present in the original path.
    """
    path = node["original_file_path"].replace("\\", "/")
    if path.startswith("marts/core/"):
        return "core"
    if path.startswith("marts/finops/"):
        return "finops"
    head = path.split("/")[0]
    return head if head in ("raw", "staging") else None


def load_models() -> tuple[dict[str, dict], nx.DiGraph]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    models: dict[str, dict] = {}
    for uid, node in manifest["nodes"].items():
        if node["resource_type"] != "model":
            continue
        layer = layer_of(node)
        if layer is None:
            continue
        models[uid] = {
            "name": node["name"],
            "layer": layer,
            "materialized": node["config"].get("materialized", "view"),
        }

    graph = nx.DiGraph()
    graph.add_nodes_from(models)
    for uid in models:
        for parent in manifest["parent_map"].get(uid, []):
            if parent in models:
                graph.add_edge(parent, uid)

    return models, graph


def assign_positions(models: dict[str, dict], graph: nx.DiGraph) -> dict[str, tuple[float, float]]:
    """One column per layer; within a column, order by average parent height."""
    columns: dict[str, list[str]] = {layer: [] for layer in LAYER_ORDER}
    for uid, meta in models.items():
        columns[meta["layer"]].append(uid)

    positions: dict[str, tuple[float, float]] = {}
    heights: dict[str, float] = {}

    for col_index, layer in enumerate(LAYER_ORDER):
        members = columns[layer]

        # Pull each node towards the mean height of its parents so edges stay
        # short and mostly horizontal.
        def sort_key(uid: str) -> tuple[float, str]:
            parents = [p for p in graph.predecessors(uid) if p in heights]
            avg = sum(heights[p] for p in parents) / len(parents) if parents else 0.0
            return (avg, models[uid]["name"])

        members.sort(key=sort_key)

        span = (len(members) - 1) * Y_GAP
        for row_index, uid in enumerate(members):
            y = span / 2 - row_index * Y_GAP
            positions[uid] = (col_index * X_GAP, y)
            heights[uid] = y

    return positions


def draw() -> None:
    models, graph = load_models()
    positions = assign_positions(models, graph)

    fig, ax = plt.subplots(figsize=(19, 11))
    fig.patch.set_facecolor("white")

    # Edges first so the boxes sit on top of them.
    for src, dst in graph.edges():
        x1, y1 = positions[src]
        x2, y2 = positions[dst]
        ax.add_patch(
            FancyArrowPatch(
                (x1 + BOX_W / 2, y1),
                (x2 - BOX_W / 2, y2),
                connectionstyle="arc3,rad=0.06",
                arrowstyle="-|>",
                mutation_scale=11,
                linewidth=0.9,
                color="#9AA4B0",
                alpha=0.75,
                zorder=1,
            )
        )

    # Model boxes.
    for uid, meta in models.items():
        x, y = positions[uid]
        mat = meta["materialized"]
        ax.add_patch(
            FancyBboxPatch(
                (x - BOX_W / 2, y - BOX_H / 2),
                BOX_W,
                BOX_H,
                boxstyle="round,pad=0.02,rounding_size=0.09",
                facecolor=COLOURS.get(mat, "#EFEFEF"),
                edgecolor=EDGE_COLOURS.get(mat, "#888888"),
                linewidth=1.3,
                zorder=2,
            )
        )
        ax.text(
            x,
            y,
            meta["name"],
            ha="center",
            va="center",
            fontsize=8.2,
            family="DejaVu Sans",
            zorder=3,
        )

    # Column headings.
    top = max(y for _, y in positions.values())
    for col_index, layer in enumerate(LAYER_ORDER):
        ax.text(
            col_index * X_GAP,
            top + 1.35,
            LAYER_TITLES[layer],
            ha="center",
            va="center",
            fontsize=11,
            fontweight="bold",
            color="#2F3B47",
            linespacing=1.5,
        )

    counts: dict[str, int] = {}
    for meta in models.values():
        counts[meta["materialized"]] = counts.get(meta["materialized"], 0) + 1

    legend = [
        mpatches.Patch(
            facecolor=COLOURS[m],
            edgecolor=EDGE_COLOURS[m],
            label=f"{m}  ({counts.get(m, 0)})",
        )
        for m in ("view", "table", "incremental")
    ]
    ax.legend(
        handles=legend,
        loc="lower center",
        ncol=3,
        frameon=False,
        fontsize=10,
        bbox_to_anchor=(0.5, -0.035),
    )

    ax.set_title(
        f"doit_demo - dbt lineage  ({len(models)} models)",
        fontsize=15,
        fontweight="bold",
        color="#1F2933",
        pad=24,
    )

    xs = [x for x, _ in positions.values()]
    ys = [y for _, y in positions.values()]
    ax.set_xlim(min(xs) - BOX_W, max(xs) + BOX_W)
    ax.set_ylim(min(ys) - 1.5, max(ys) + 2.3)
    ax.axis("off")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT_PNG, dpi=200, bbox_inches="tight", facecolor="white")
    fig.savefig(OUTPUT_SVG, bbox_inches="tight", facecolor="white")
    plt.close(fig)

    print(f"{len(models)} models, {graph.number_of_edges()} dependencies")
    print(f"wrote {OUTPUT_PNG.relative_to(ROOT)}")
    print(f"wrote {OUTPUT_SVG.relative_to(ROOT)}")


if __name__ == "__main__":
    draw()
