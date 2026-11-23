Fixtures in this directory are copied from
`OpenTimelineIO/otio-fcpx-xml-adapter` PR `#7` at commit
`20d9fa54141149c09d976f3520a8c29d8e5ad124`.

Source paths:
- `tests/sample_data/fcpx_transitions.fcpxml`
- `tests/sample_data/Test Library.fcpxmld/Info.fcpxml`

The upstream repository is Apache-2.0 licensed.

The fixtures use FCPXML 1.14. To run the integration tests from SpliceKit's root
with the matching adapter, install `opentimelineio` in your Python environment
and point it at the plugin manifest in a checkout of the revision above.

```sh
export OTIO_PLUGIN_MANIFEST_PATH="/path/to/otio-fcpx-xml-adapter/src/otio_fcpxml_adapter/plugin_manifest.json"
python3 -m unittest discover -s Tests -p test_otio_upstream_fixtures.py
```
