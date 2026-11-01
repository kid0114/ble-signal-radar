# Architecture and staged RF expansion

## Scope and status

BLE Signal Radar remains a macOS BLE search utility. The preliminary refactor introduces real boundaries for the existing collectors; it does **not** add an SDR, remote collector, recorder, spectrum detector, map, or localization engine. The shared contracts are intentionally small and provisional until a second measurement family is validated.

“Remote sensing” here means passive RF spectrum monitoring and spatial surveying, not an implemented radar, imaging system, or satellite-data platform. Software cannot expand a receiver's physical frequency coverage.

## Current structure

```text
Sources/
  App/                 application lifecycle and existing local settings
  Core/                typed observation envelope and backend contract
  Backends/
    BLE/               CoreBluetooth collection and discovery models
    AirPods/           optional Apple payload/log parsing and owned log process
  Analysis/            existing BLE-oriented RSSI history and distance model
  UI/                  window controller, device picker, graph
Resources/             Info.plist and localized Bluetooth permission strings
Tests/                 offline unit tests and explicitly synthetic fixtures
docs/                  runtime screenshots and this engineering plan
```

`build.sh` and `test.sh` remain the root entry points. The generated `.app` and private `config.local.json` remain beside each other at the project root. Bundle identity, persisted configuration keys, default distance assumptions and freshness thresholds remain unchanged. A separately requested 32-point header row displays the selected target's available name and full identifier; existing controls keep their relative spacing and footer margin. The identifier remains visible without fresh samples, while a device name is shown only when available in discovery records. It does not establish presence or ownership.

### Ownership

- `SignalRadarApp` / `AppDelegate`: launch, close-to-quit behavior, shutdown coordination.
- `BLEScanner`: own the CoreBluetooth manager, collect advertisements, expose status and a bounded discovery list. Do not choose the user's target or interpret Apple payloads here.
- `AirPodsLogBackend`: own only its `/usr/bin/log` subprocess; frame/decode its output, reject wrong/old/duplicate events, report failures, and invalidate queued callbacks when stopped. Deduplication survives restarting the same backend session.
- `trackingTargetText`: a tested, bilingual presentation helper for selected BLE identity, optional accessory configuration or no-selection state; no private identity is compiled in.
- `SignalWindowController`: preserve current target selection, calibration, settings, and existing measurement presentation behavior. It converts typed observations into the current RSSI view. Moving these feature policies into an independently testable session engine is a later step, not already completed.
- `SignalHistory`: ordered, bounded RSSI samples and freshness/smoothing. No Apple log schema or `AdTsMC` deduplication.
- `DistanceParameters`: the existing BLE-oriented propagation model. It is not instrument calibration and must not become the default estimator for arbitrary RF payloads.

The app still compiles as one executable, not separately enforced SwiftPM targets. `test.sh` additionally compiles `Sources/Core/` independently to catch accidental dependencies on app settings, UI, or concrete backends.

## Observation and backend contracts

The active data path is:

```text
CoreBluetooth advertisements ──> Observation<BLEAdvertisement> ──┐
                                                               ├─> target policy / RSSI view ─> UI
Optional bluetoothd log ───────> Observation<TargetEvent> ────────┘
```

`Observation<Payload>` keeps a common `ObservationContext` next to a backend-owned, typed payload. The context currently carries:

- Observation UUID and acquisition-session UUID.
- Logical receiver-channel ID.
- Observation time and local arrival time separately.
- Time basis: receiver callback or system event.
- Provenance: live, replay, or synthetic.

Both production collectors emit **live** observations. Other provenance values make test/future data origins explicit; they do not imply a replay feature exists. Test fixtures run only in the command-line test process.

Receiver IDs such as `local.corebluetooth` identify local channels, not globally unique physical receivers, authenticated transmitters, or independent antennas. Before distributed collection, introduce persistent receiver identity and explicit clock domains/uncertainty.

CoreBluetooth timestamps are callback times, **not hardware RF capture timestamps**. A system-event timestamp is likewise not a guaranteed over-the-air packet timestamp. Unknown timing precision stays unknown.

The current UI retains only its narrow RSSI projection. The full observation envelope is transient; durable recording, complete provenance retention, and a versioned export schema are **not implemented**.

`SensorBackend` defines typed delivery and start/stop lifecycle. `SensorDescriptor` currently reports logical identity and implemented measurement kinds only. It does not claim RF tuning range, calibrated power, raw IQ, direction finding, or receiver pose. Callbacks from the two current collectors arrive on the main queue. This contract is not a dynamic plugin loader or a high-throughput IQ bus.

## Rules for expansion

### Preserve measurement semantics

Do not flatten new measurements into `SignalSample` or a large object full of unrelated optional fields. Add a payload with its actual units, instrument configuration, and validation rules alongside a real adapter.

- BLE advertisement: receiver-scoped identifier and reported RSSI in dBm; advertised names/company codes do not authenticate ownership. Current CoreBluetooth collection does not supply an absolute RF channel.
- Spectrum frame: frequency axis, power/unit, resolution or effective noise bandwidth, acquisition interval, tuning/gain/AGC state, antenna/front-end configuration, and calibration reference where known.
- IQ capture: reference to chunked data plus encoding, sample rate, tuning, clock and discontinuity metadata. Do not forward individual samples through UI callbacks.
- Bearing/range: only when supported by actual hardware; preserve its coordinate frame, uncertainty, method and calibration.

Unknown identity, frequency, pose, or calibration must remain unknown. SDR dBFS is not interchangeable with dBm; power per bin is not automatically power spectral density. Never apply the BLE propagation formula indiscriminately to another band.

### Keep measurement and inference separate

Detection, classification, target association, and localization are different outputs with separate validation. An energy peak is not a device count or authenticated identity. A model's result should reference its input observations, configuration/model version, and assumptions, without rewriting those inputs.

Instrument calibration describes the receiver/antenna/front-end response. Propagation calibration describes an emitter and environment. Store and version them separately when recording is introduced.

A survey heatmap describes measurements at receiver positions. It is not automatically a transmitter-location estimate or a statistically calibrated confidence region.

### Separate low-rate events and bulk data

For one future external receiver, prefer a dedicated adapter/worker process if its driver or DSP ecosystem is unsuitable for the Swift UI. Select its implementation language after selecting hardware and processing needs.

- Low-rate metadata/results: typed observations and status events.
- Bulk IQ/high-rate spectra: bounded worker queues and chunked storage with references.
- Both paths: observable drops/gaps, bounded retention and explicit configuration changes.

Do not choose a remote protocol or promise throughput before measuring one receiver's data rate. Native Swift adapters remain appropriate where practical; a separate process is not mandatory for every sensor.

## Staged implementation plan

### Stage 1 — structural foundation (preliminary implementation)

- [x] Organize sources, resources and tests without changing root build/run commands.
- [x] Separate lifecycle, window/graph UI, BLE collection, optional AirPods support and distance mathematics.
- [x] Use typed observation envelopes in both existing production collection paths.
- [x] Move Apple event framing/deduplication out of RSSI history; guard stopped-stream callbacks.
- [x] Compile the shared core independently and extend offline regression tests.
- [ ] Complete broader physical-device, picker/calibration and lifecycle validation before treating the refactor as a release.

Automated tests establish software behavior only, not RF detection coverage or physical ranging accuracy. Live UI smoke checks supplement, not replace, compatibility experiments.

### Stage 2 — session engine, recording and BLE surveys (planned)

Extract target/session policy from the window controller, then implement:

1. Per-target history and propagation references, scoped by receiver and association context; no silent identifier merging.
2. Versioned recording/export and clearly labeled replay, including enough configuration/provenance to interpret each observation. Protect original measurements; inferred outputs are separate.
3. An optional receiver-pose record with coordinate frame, units, timestamp and uncertainty. Begin with user-marked positions on a scaled 2D floor plan.
4. Tests for target changes, stale/reordered data, settings failures, configuration revisions and recording/replay fidelity.
5. Later UI string centralization once the collection/session boundaries are stable.

Keep target motion and receiver motion distinguishable. Start survey validation with a known stationary target. Current GUI behavior does not need to wait for any RF hardware project.

### Stage 3 — one external RF measurement family (planned feasibility gate)

Agree on one use case, one band and one receiver/antenna/front-end combination before implementation or purchase. Establish supported tuning range, instantaneous bandwidth, sweep/dwell gaps, sensitivity, gain behavior and calibration limitations.

Add one real adapter and spectrum payload. Evaluate live collection and reviewed recordings, drop reporting, repeatability and power units before attempting anomaly detection or spatial inference. Extend descriptors with verified frequency/settings capabilities at this stage, rather than filling speculative capabilities now.

Acceptance criteria and numerical thresholds must be agreed before running the experiment. A wider tuning range does not mean simultaneous observation of every frequency, and a swept receiver may miss brief transmissions.

### Stage 4 — remote receivers and reviewed inference (planned)

Separate transport from receiver drivers. Define persistent receiver identity, authentication/encryption, sequence and restart behavior, buffering/reconnect policy, clock domains, clock uncertainty, receiver pose and data retention.

Arrival time is not capture time. Ordinary network clock alignment must not be advertised as sufficient for phase-coherent or TDOA localization. Such methods require a separate hardware/time-synchronization feasibility study.

Evaluate environmental baselines and false alarms before calling deviations anomalous. Compare spatial guidance against raw RSSI/survey baselines in held-out environments before making room/floor/distance claims. Multiple receivers or a 3D view do not create missing localization information.

## Privacy and non-goals

Keep private identifiers, raw nearby-device records, floor plans, coordinates and IQ captures local by default. Root `recordings/` and `exports/` paths are ignored in advance; those ignore rules do not implement a recorder or guarantee all sensitive filenames are protected. Shared fixtures must be fictional or deliberately reviewed/sanitized.

Start with passive observation in permitted bands using owned or explicitly authorized equipment. Transmission, jamming, interception/decryption of private communications, hardware purchase, deployment, and publication of datasets are not authorized by this plan.

No general plugin framework, mandatory network service, database server, SwiftPM/Xcode migration, or empty SDR/remote/map directory is required for this first pass. Revisit packaging and module boundaries when a real second measurement family makes the need concrete.
