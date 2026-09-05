# Changelog

All notable changes to this project will be documented in this file.

## [0.3.1]

### Fixed

- Support `async` down to 2.32 (the gemspec minimum):
  `Promise#wait(timeout:)` only exists on newer releases, so timed
  waits now fall back to `with_timeout` around a blocking wait.
- Faster connection close: stop the listen task before joining it
  (it never exits on its own while the peer is alive). Full suite
  went from ~35s down to ~6s.

### Compatibility

- Verified: full suite (189 tests) green on Ruby 3.2, 3.3, 3.4 and 4.0,
  with `async` 2.32, 2.36, 2.37, 2.38 and 2.45.

## [0.3.0]

### Added

- New `ACP::Contrib` helpers: `ToolCallTracker`, `SessionAccumulator`,
  `PermissionBroker` (+ `default_permission_options`).
- `Client#set_config_option` alias for `set_session_config_option`
  (short alias for the same wire method).
- `Agent#create_elicitation` now also accepts `message:` + `mode:`
  kwargs next to the full request hash/model.
- `Agent#write_text_file` / `#release_terminal` / `#kill_terminal`
  return `nil` on null responses instead of an empty model.
- RuboCop config (`rake rubocop`), SimpleCov gate (90% minimum),
  GitHub Actions matrix (Ruby 3.2, 3.3, 3.4, 4.0).

### Fixed

- Works with any `async` 2.x: task cancellation supports both
  `Async::Stop` (older) and `Async::Cancel` (newer); timed join no
  longer relies on `Task#wait(timeout:)`. Previously `close` could
  hang forever on older async releases.
- `MemoryTransport#close` signals EOF to the peer only; local reads
  drain queued messages first.
- `NdjsonTransport` receive timeout now covers partial lines
  (previously a line without `\n` hung forever).
- Outgoing observer events fire after a successful send and receive a
  deep copy, so observers can neither see unsent payloads nor mutate
  the wire format.
- `handle_response` prefers `result` over `error` when both are present
  and resolves `nil` when neither is present.
- Parallel shutdown of handler tasks instead of sequential grace waits.
- `Router` no longer coerces missing (`nil`) params to `{}`; they fail
  validation as `invalid_params` instead of being silently replaced.
- Schema models validate `required` fields in `.new`, reject
  catch-all `Other*` values reserved by known variants
  (`action: accept`, `mode: form`, …), and apply `default_on_error`
  on direct construction too.
- Schema generator output is byte-identical on every Ruby
  (`Hash#inspect` spacing changed in Ruby 3.4).

### Compatibility

- Verified: full suite (189 tests) green on Ruby 3.2, 3.3, 3.4 and 4.0,
  with `async` 2.37 and 2.45.

## [0.2.0]

- Initial Ruby SDK snapshot: typed schema models, JSON-RPC connection
  over NDJSON, client/agent wrappers, stdio process management.
