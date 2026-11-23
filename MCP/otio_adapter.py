"""Optional OpenTimelineIO conversion for SpliceKit. Reads and writes JSON on standard I/O."""

import json
from pathlib import Path
import sys


def _otio_prepare_for_fcp(timeline):
    """Prepare an OTIO timeline for FCP import.

    - Converts non-title GeneratorReference clips to gaps
    - Preserves title generators (the adapter writes them as <title> elements)
    - Returns the modified timeline (in-place)
    """
    import opentimelineio as otio
    if not isinstance(timeline, otio.schema.Timeline):
        return timeline
    for track in timeline.tracks:
        for i, item in enumerate(list(track)):
            if (isinstance(item, otio.schema.Clip) and
                    isinstance(item.media_reference, otio.schema.GeneratorReference)):
                if not _otio_is_title_generator_reference(item.media_reference):
                    track[i] = otio.schema.Gap(source_range=item.source_range)
    return timeline


def _otio_is_title_generator_reference(media_reference):
    """Detect title-like GeneratorReference metadata across adapter variants."""
    title_generator_kinds = {"Title", "title", "fcpx.title"}
    gen_kind = getattr(media_reference, "generator_kind", "")
    if gen_kind in title_generator_kinds:
        return True

    parameters = getattr(media_reference, "parameters", {}) or {}
    if not isinstance(parameters, dict):
        return False
    return bool(parameters.get("text_xml") or parameters.get("text_style_def_xml"))


def _otio_fcpx_adapter_candidates():
    """Return compatible FCPXML adapter names in preference order."""
    import opentimelineio as otio

    preferred = ("fcpxml", "fcpx_xml")
    try:
        available = set(otio.adapters.available_adapter_names())
    except Exception:
        available = set()

    ordered = [name for name in preferred if name in available]
    if ordered:
        return ordered
    return list(preferred)


def _otio_with_fcpx_adapter(operation):
    """Run an OTIO adapter operation against the supported FCPXML adapter names."""
    errors = []
    for adapter_name in _otio_fcpx_adapter_candidates():
        try:
            return operation(adapter_name)
        except Exception as exc:
            errors.append(f"{adapter_name}: {exc}")
    raise RuntimeError("No working FCPXML adapter found (" + "; ".join(errors) + ")")


def _otio_read_fcpx_string(fcpxml_str):
    """Read FCPXML using whichever adapter name is installed."""
    import opentimelineio as otio

    return _otio_with_fcpx_adapter(
        lambda adapter_name: otio.adapters.read_from_string(fcpxml_str, adapter_name)
    )


def _otio_write_fcpx_string(timeline, fcpxml_version=None):
    """Write FCPXML using whichever adapter name is installed.

    The modern PR #7 adapter accepts ``fcpxml_version`` for version-aware
    FCPXML 1.0-1.14 output. Older adapters reject that kwarg, so retry without
    it before moving to the next adapter name.
    """
    import opentimelineio as otio

    def write(adapter_name):
        if fcpxml_version:
            try:
                return otio.adapters.write_to_string(
                    timeline,
                    adapter_name,
                    fcpxml_version=fcpxml_version,
                )
            except TypeError as exc:
                if "fcpxml_version" not in str(exc):
                    raise
        return otio.adapters.write_to_string(timeline, adapter_name)

    return _otio_with_fcpx_adapter(write)


def _otio_fcpxmld_info_path(package_path):
    """Return the FCPXML document entrypoint for a `.fcpxmld` package."""
    from pathlib import Path

    package = Path(package_path)
    if not package.exists():
        raise FileNotFoundError(f"FCPXML package does not exist: '{package}'.")
    if not package.is_dir():
        raise NotADirectoryError(f"FCPXML package path is not a directory: '{package}'.")

    info_path = package / "Info.fcpxml"
    if not info_path.is_file():
        raise FileNotFoundError(f"FCPXML package is missing 'Info.fcpxml': '{package}'.")
    return info_path


def _otio_read_fcpx_document(path):
    """Read a `.fcpxml` document or `.fcpxmld` package entrypoint."""
    from pathlib import Path

    document_path = Path(path)
    if document_path.is_dir() or document_path.suffix.lower() == ".fcpxmld":
        document_path = _otio_fcpxmld_info_path(document_path)

    return document_path.read_text(encoding="utf-8")


def _otio_fcpxml_clean_for_paste(fcpxml_str):
    """Clean FCPXML for FCP's pasteboard import.

    - Strips <library> wrapper (pasteboard merges into active library)
    - Strips standalone <asset-clip> elements at event level (browser clutter)
    """
    lines = fcpxml_str.split("\n")
    clean = []
    for line in lines:
        s = line.strip()
        if s in ("<library>", "</library>"):
            continue
        if s.startswith("<asset-clip ") and s.endswith("/>"):
            if (len(line) - len(line.lstrip())) <= 16:
                continue
        clean.append(line)
    return "\n".join(clean)


def _otio_first_timeline(result):
    """Extract the first Timeline from an OTIO read result."""
    timelines = _otio_all_timelines(result, collection_fallback=False)
    if timelines:
        return timelines[0]
    return result

def _otio_all_timelines(result, collection_fallback=True):
    """Extract all Timelines from an OTIO read result."""
    import opentimelineio as otio
    if isinstance(result, otio.schema.Timeline):
        return [result]
    if isinstance(result, otio.schema.SerializableCollection):
        timelines = []
        if hasattr(result, "find_children"):
            timelines = list(result.find_children(descended_from_type=otio.schema.Timeline))
        if not timelines:
            timelines = [
                child
                for item in result
                for child in _otio_all_timelines(item, collection_fallback=False)
            ]
        if timelines:
            return timelines
        return list(result) if collection_fallback else []
    return [result] if collection_fallback else []

def _otio_timeline_summary(timeline):
    """Build a summary dict for an OTIO timeline."""
    import opentimelineio as otio
    info = {"name": getattr(timeline, "name", "unknown")}
    if isinstance(timeline, otio.schema.Timeline):
        info["tracks"] = len(timeline.tracks)
        info["clips"] = len(list(timeline.find_clips()))
        total_dur = timeline.duration()
        if total_dur and total_dur.value > 0 and total_dur.rate > 0:
            info["duration_seconds"] = round(total_dur.value / total_dur.rate, 3)
    return info


def _otio_detect_rate(timeline):
    """Auto-detect frame rate from an OTIO timeline. Returns 24 as default."""
    import opentimelineio as otio
    raw_rate = 24
    if isinstance(timeline, otio.schema.Timeline):
        for clip in timeline.find_clips():
            if clip.source_range and clip.source_range.duration.rate > 1:
                raw_rate = clip.source_range.duration.rate
                break
        else:
            dur = timeline.duration()
            if dur and dur.rate > 1:
                raw_rate = dur.rate
    return _otio_normalize_rate(raw_rate)


def _otio_normalize_rate(rate):
    """Map common approximate frame rates to exact SMPTE values.

    The FCPXML adapter returns integer rates (29 for 29.97fps) and user input
    may use approximate values (29.97). The EDL adapter needs exact fractional
    rates (30000/1001) for drop-frame timecode support.
    """
    rate_map = {
        23: 24000 / 1001,    # 23.976
        23.98: 24000 / 1001,
        23.976: 24000 / 1001,
        24: 24,
        25: 25,
        29: 30000 / 1001,    # 29.97 (FCPXML adapter returns 29)
        29.97: 30000 / 1001,
        30: 30,
        47: 48000 / 1001,
        47.95: 48000 / 1001,
        48: 48,
        50: 50,
        59: 60000 / 1001,    # 59.94
        59.94: 60000 / 1001,
        60: 60,
    }
    # Check exact match first, then closest integer
    if rate in rate_map:
        return rate_map[rate]
    rounded = round(rate)
    if rounded in rate_map:
        return rate_map[rounded]
    return rate

def convert(request):
    import opentimelineio as otio

    path = request.get("path", "")
    rate = request.get("rate") or 0
    extension = Path(path).suffix.lower()
    if request["operation"] == "export":
        timeline = _otio_first_timeline(_otio_read_fcpx_string(Path(request["source"]).read_text(encoding="utf-8")))
        options = {"rate": _otio_normalize_rate(rate) if rate > 0 else _otio_detect_rate(timeline)} if extension == ".edl" else {}
        otio.adapters.write_to_file(timeline, path, **options)
        return {**_otio_timeline_summary(timeline), "status": "ok", "format": extension.lstrip("."),
                "path": path, "bytes": Path(path).stat().st_size}

    if request["operation"] != "import":
        raise ValueError("Unknown adapter operation")
    if path:
        options = {"rate": _otio_normalize_rate(rate) if rate > 0 else 24} if extension == ".edl" else {}
        result = otio.adapters.read_from_file(path, **options)
    else:
        result = otio.adapters.read_from_string(request["otio_json"], "otio_json")
    documents = []
    for timeline in _otio_all_timelines(result):
        try:
            _otio_prepare_for_fcp(timeline)
            xml = _otio_fcpxml_clean_for_paste(_otio_write_fcpx_string(timeline))
            documents.append({"xml": xml, "summary": {**_otio_timeline_summary(timeline), "converter": "python_adapter"}})
        except Exception as exc:
            documents.append({"error": str(exc), "summary": {"name": getattr(timeline, "name", "unknown")}})
    if not documents:
        raise ValueError("No timelines found in the input")
    return documents


if __name__ == "__main__":
    try:
        if len(sys.argv) == 1:
            json.dump(convert(json.load(sys.stdin)), sys.stdout)
        elif len(sys.argv) == 4 and sys.argv[1] == "export":
            convert({"operation": "export", "source": sys.argv[2], "path": sys.argv[3]})
        elif len(sys.argv) == 4 and sys.argv[1] == "import":
            import opentimelineio as otio
            timeline = _otio_first_timeline(otio.adapters.read_from_file(sys.argv[2]))
            Path(sys.argv[3]).write_text(_otio_write_fcpx_string(timeline), encoding="utf-8")
        else:
            raise ValueError("Expected JSON on stdin or import/export <source> <destination>")
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
