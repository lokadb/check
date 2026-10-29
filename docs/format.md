# The report format of `lokadb check -json`

The format is versioned by `schema_version`, now `1`. The JSON Schema is [../schema/report-v1.schema.json](../schema/report-v1.schema.json); every finding code `lokadb` makes is in [../schema/codes.txt](../schema/codes.txt), the codes it no longer makes in [../schema/codes-retired.txt](../schema/codes-retired.txt). Both lists are generated from the tests of `lokadb` that pin the format.

## Compatibility rules

- `schema_version` grows only on an incompatible change: a field removed, renamed, or of another type or meaning; a finding code renamed or removed.
- **Adding** a field, a finding code, a subject kind or a value of an open list is compatible and keeps the version. A consumer must skip fields and codes it does not know.
- A finding's `code` never changes. A code `lokadb` stops making moves to `codes-retired.txt` and is never reused for another finding.
- `message`, `examples`, `fanout_policy` and `workload_sources` are for people: their wording changes freely, do not parse them.
- `severity`, `verdict` and a table's `state` are closed lists: a new value would be an incompatible change.
- **Privacy.** No field holds values from data rows: only object names, counts, and SQL normalized with constants replaced by `$n`. Known exceptions: the `examples` of `unique_not_tenant_scoped` hold an index definition (`pg_get_indexdef`), where a partial index may have a constant in its `WHERE`; and SQL recorded by the proxy from the simple query protocol keeps the literals of the query text.

## Top level

| field | type | meaning |
|---|---|---|
| `schema_version` | int | `1` |
| `lokadb_version` | string | the build of `lokadb` that made the report |
| `database` | string | the SaaS's (cloud) database |
| `verdict` | `ready` \| `review` \| `unsupported` \| `blocked` \| `invalid_spec` | exit codes 0 / 2 / 4 / 3 / 5 |
| `summary` | object | counts: tables (ready, not supported), global unique constraints that become per organization, query patterns (without the organization, refused by the proxy), transaction shapes (writing cloud and moved tables together) |
| `tables[]` | object | the spec's tables: `name`, `schema`, `tenant` (how its rows find their organization), `rows_estimate` (-1: not counted), `ready`, `state` (`ready`, `review`, `unsupported`, `blocked`, `spec_error`) |
| `suggested_spec` | object | with `-tenant-column` or `-org-table`: the spec found |
| `discovery` | object | only with `-org-table`: `org_table`, `key`, `key_kind` (`int`/`uuid`), `spec`, and `tables[]`, one entry per table of the database: `table`, `role` (`organization`, `root`, `child`, `cloud`, `ambiguous`), `column`, `parent`, `path` (up to the organizations table), `basis` (`fk`, or `name`: a column named by the convention, verified on the data), `code` and `reason` (why the table stays in the cloud or is ambiguous), `options[]` (`column`, `target`), `nullable_path` and `rows_without_parent` (the only path to the parent is a column that may be NULL, and how many rows hold NULL there and would not move) |
| `spec` | object | the spec the report was computed with (not after `enable`) |
| `suggested_routing` | object | with `-suggest`: every suggested declaration as one patch (`relations[]`, `keys[]`, `cloud_tables[]`); `-suggest FILE` writes it, `-patch FILE` judges the workload as if it were declared |
| `workload_sources[]` | string | where the queries came from, for people |
| `fanout_policy`, `fanout` | string, object | the proxy's policy for queries without an organization: `mode`, `allow[]` (fingerprints, sorted), `source` (the config file or `default`). With `spec` and `lokadb_version` it lets two reports be compared fairly |
| `findings[]` | object | sorted: `spec_error`, `blocker`, `unsupported`, `change`, `warning`, `info` |
| `ci` | object | only with `-ci` |
| `profile` | object | only with `-profile` |
| `latency` | object | only with `-rtt` |

## A finding

| field | meaning |
|---|---|
| `severity` | `spec_error` (the spec does not match the database), `blocker` (stops the move whatever LokaDB does), `unsupported` (a limitation of LokaDB, not a problem of the schema), `change` (works, but behaves differently after the move), `warning`, `info` |
| `code` | never renamed |
| `key` | a stable key for a baseline: the code and the object, the same across runs and machines. Built from `subject`, not from the text. A query pattern's own key is `code:fp:<fingerprint>` |
| `object` | the object for people; `subject` is the machine-readable form |
| `subject` | what the finding is about (below); absent for findings about the database as a whole |
| `message`, `examples` | for people; `examples` are cut (at most 8, then "… and N more") |
| `patterns[]` | for findings about query patterns: every pattern, uncut |
| `transactions[]` | for `mixed_write_transaction` and `ddl_then_write_transaction`: the transaction shapes |
| `measure` | for `tenant_null` and `orphan_rows`: how many rows and how they were counted (`exact` or sampled) |
| `suggestion` | for `routing_suggestion`: the declaration (`kind`: relation, cloud_table, key; `routing`), its data check, the patterns it routes and their calls |

### `subject`

| `kind` | fields | example codes |
|---|---|---|
| `column` | `schema`, `table`, `column` | `tenant_null`, `child_without_fk`, `id_type` |
| `table` | `schema`, `table` | `orphan_rows`, `table_rule`, `rls_policy`, `materialized_view` |
| `constraint` | `schema`, `table`, `constraint`, `columns[]`; a foreign key also `ref_schema`, `ref_table`, `ref_columns[]` | `unique_not_tenant_scoped`, `fk_multicolumn` |
| `index` | `schema`, `table`, `columns[]` (the index that is missing) | `feed_index` |
| `database` | `database`, `side` (`cloud` or `customer`) | `customer_collation_differs`, `customer_connected` |
| `role` | `role`, `side` | `customer_app_superuser`, `customer_privileges` |
| `extension` | `extension`, `side` | `cloud_postgres_fdw` |
| `setting` | `setting`, `side` | `cloud_wal_level` |
| `schema` | `schema`, `side` | `customer_schema` |
| `file` | `path` | `workload_empty`, `recording_truncated` |
| `tables` | `cloud_tables[]`, `lokadb_tables[]` | `mixed_write_transaction` |
| `reason` | `reason` | `profile_fdw_reason` |
| `pattern` | `fingerprint` | `latency_n_plus_one` |
| `transaction` | `fingerprint`: the statements' fingerprints, sorted, joined by `+` | `latency_expensive_transaction` |

**Partitions.** When the object is a partition, `subject` names its parent in `partition_of`, and the same findings of the partitions of one parent are merged into one on the parent.

## `patterns[]`

`fingerprint` (the pg_query fingerprint the proxy's `allow` list matches; empty when the statement does not parse), `sql` (the most executed normalized text, uncut), `calls`, `write`, `tables` (the moved tables it touches), `roles` and `sources` (when the source tells), `note` (why the proxy refuses it), `gaps` (why the proxy finds no organization: `kind`, `table`, `column`, `form` such as `=` or `IN`).

## `transactions[]`

`cloud_tables[]`, `lokadb_tables[]`, `shapes` (how many shapes write these tables), `count` (transactions seen), `statements[]` of the most frequent shape in order (`fingerprint`, `sql`, `write`, `tables`). Only from the proxy's recording: `pg_stat_statements` has no transaction boundaries.

## `ci`

With `-ci`: `baseline` (the file, empty without one), `new[]` (items the baseline has not accepted, each with `key`, `severity`, `code`, `pattern` for query items, and a `hint`), `stale[]` (accepted items no longer found), `accepted`, `accepted_without_reason`. Exit code 0 when nothing is new, 6 otherwise. `info` items do not take part.

## `profile`

With `-profile fdw|fdw+direct|direct`: the profile, and how many query patterns and calls the direct path would take; findings `profile_*` say what keeps the rest on the FDW path or refuses them.

## `latency`

With `-rtt <ms>`: `rtt_ms`, `model` (`estimate`), `exchanges` (the exchanges with the organization's database the model counts per statement kind), `transactions[]` (most expensive first: `count`, `statements[]` with their kind, repeats per transaction, exchanges on FDW, on the direct path now, and at the direct path's limit, and the same in ms), `total_fdw_ms`, `total_direct_ms`, `total_target_ms`. Findings: `latency_estimate`, `latency_expensive_transaction`, `latency_n_plus_one`, `latency_no_recording`; all `info`, they never change the verdict.
