# lokadb check

[![CI](https://github.com/lokadb/check/actions/workflows/ci.yml/badge.svg)](https://github.com/lokadb/check/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

`lokadb check` tells you, before anything changes, whether the organizations of your SaaS database can move into their own databases with [LokaDB](https://github.com/lokadb/lokadb), and what would behave differently. It reads the schema, the catalog and your application's recorded queries; it never changes your database. It is open source and part of every `lokadb` binary and image.

This repository has:

- **a GitHub Action** that runs `lokadb check` on every pull request of your application, fails the job on blockers (or on anything your CI baseline has not accepted) and posts the summary;
- **the report format**: the JSON Schema of `lokadb check -json` ([schema/report-v1.schema.json](schema/report-v1.schema.json)), every finding code ([schema/codes.txt](schema/codes.txt)) and real sample reports ([samples/](samples/));
- **the documentation** of check ([docs/check.md](docs/check.md)) and of the format ([docs/format.md](docs/format.md)).

The code of `lokadb` and of check itself is in [lokadb/lokadb](https://github.com/lokadb/lokadb).

## The GitHub Action

```yaml
name: lokadb check
on: pull_request
jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write   # only for comment: true
    steps:
      - uses: actions/checkout@v4
      # run your tests through the LokaDB proxy with -record workload.json first, or keep a recording in the repository
      - uses: lokadb/check@v1
        with:
          db: ${{ secrets.LOKADB_CHECK_DSN }}   # admin DSN of a copy of your database (staging, a restored dump)
          spec: lokadb/spec.json
          workload: lokadb/workload.json
          baseline: lokadb/accepted.json        # optional: fail only on what is new
          comment: true
```

| input | | default |
|---|---|---|
| `db` | admin DSN of the SaaS's database. Use a secret; it reaches lokadb through an environment variable (`-db env:LOKADB_DB`), never on the command line | required |
| `spec` | the tables spec | |
| `tenant-column` | without a spec: the organization column the tables are discovered by | |
| `workload` | the proxy's recordings (`lokadb proxy -record`), comma-separated | |
| `proxy-config` | the proxy's config, for its policy on queries without an organization | default policy: reject |
| `baseline` | a CI baseline (`lokadb check -write-baseline`): the job fails only on items it has not accepted | |
| `fail-on` | without a baseline: `blocked` (blocked, invalid spec), `unsupported` (also "not supported by LokaDB yet"), `review` (also "needs review") | `blocked` |
| `args` | more arguments, e.g. `-rtt 20` (latency forecast) or `-profile fdw+direct` | |
| `json` | also write the JSON report to this path | |
| `version` | the `lokadb` release, `v0.1.0` or `latest` | `latest` |
| `image` | run `lokadb` from this container image instead of the release binary | |
| `comment` | on a pull request, post the summary as one comment, updated on each run | `false` |

Outputs: `verdict` (`ready`, `review`, `unsupported`, `blocked`, `invalid_spec`; with a baseline `ok` or `new`), `exit-code`, `report` (the text report's path). The summary of every run is in the job's summary page.

The database `check` reads should be a copy (staging, a restored dump): `check` only reads, and every probe of rights it makes runs in a transaction that is rolled back, but it needs the admin role of that database to see the catalog as `enable` and `move-org` would.

### A CI baseline

Accepting what you reviewed, so that the job fails only on what is new:

```bash
lokadb check -db "$DSN" -spec lokadb/spec.json -workload lokadb/workload.json -write-baseline lokadb/accepted.json
```

Each item of `accepted.json` can carry a reason. Query patterns are matched by their fingerprint, so constants and list lengths do not matter. See [docs/check.md](docs/check.md#json-and-ci).

## The report format

`lokadb check -json` prints a report of `schema_version` 1:

- the **verdict** (`ready`, `review`, `unsupported`, `blocked`, `invalid_spec`, with exit codes 0, 2, 4, 3, 5) and a summary;
- the **tables** of the spec with their state;
- the **findings**, each with a severity, a code that is never renamed, a stable `key`, the object in parsed form (`subject`), and where it applies the query patterns (with their pg_query fingerprints), transaction shapes, row counts, a suggested routing declaration;
- with `-rtt` the **latency** forecast, with `-profile` the **profile** estimate, with `-ci` the **ci** result.

A consumer must skip fields and codes it does not know: new ones are added without a new `schema_version`. The report holds no values from data rows: only names, numbers and SQL with constants replaced by `$n`. Details: [docs/format.md](docs/format.md).

### Samples

Real reports of `lokadb check`, with their inputs in [samples/input/](samples/input/):

| report | what it shows |
|---|---|
| [samples/badapp.json](samples/badapp.json) | a schema with problems planted on purpose: a key type LokaDB does not take yet (`unsupported`), rows without a parent, a global unique constraint, row security, triggers, a view |
| [samples/chat-rtt-suggest.json](samples/chat-rtt-suggest.json) | a recorded workload with `-rtt 20 -suggest`: a query without the organization (`blocked`), the relation that fixes it suggested with its data check, a feed without an index, a mixed transaction, the latency forecast with an N+1 chain |
| [samples/chat-ci.json](samples/chat-ci.json) | the same with `-ci` and no baseline: every item is new |
| [samples/chat-rtt.txt](samples/chat-rtt.txt) | the text report of the same run |

## License

Apache-2.0: [LICENSE](LICENSE), [NOTICE](NOTICE).
