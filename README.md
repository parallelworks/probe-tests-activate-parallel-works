# PROBE tests for activate.parallel.works

This repository holds the PROBE test definitions for the `activate.parallel.works`
platform: one JSON file per test under `tests/`. A test launches one workflow of
[parallelworks/workflows](https://github.com/parallelworks/workflows) with fixed inputs
on one system; it passes when the run completes.

PROBE itself (the runner, the dashboards and the platform workflows that run them)
lives in [parallelworks/workflows under `workflows/probe`](https://github.com/parallelworks/workflows/tree/canary/workflows/probe).
Its workflows fetch this repository at run time, so a change pushed here is picked up
by the next run and by `Refresh` on the dashboard. Results go to the bucket
`pw://alvaro/gcpbucket` under `probe/results`.

## Layout

```
tests/<platform>/<user>/<workflow_name>/<name>.json   one test
.github/workflows/run-tests.yml                      action: run all or selected tests on the platform
.github/workflows/dashboard.yml                      action: start the results dashboards
```

The test id `<platform>/<user>/<workflow_name>/<name>` comes from the file's fields, not
from its location; the path above is the recommended place. Only tests whose `platform`
and `user` match the account that runs them are executed, so every file here has
`"platform": "activate.parallel.works"`.

## Run the tests

| How | What happens |
|---|---|
| GitHub action **Run PROBE tests** | Runs `workflows/probe/yamls/general_run_tests.yaml` from `parallelworks/workflows` on the platform with the tests of this branch, waits, and turns red when a test fails. `selection` is `all` or test files relative to `tests/`, separated by spaces. |
| Admin dashboard | `Run all`, or open a test and `Rerun test`. Start the dashboards with the GitHub action **Start PROBE dashboard**; the run completes once the endpoints `probe-<run slug>` and `probe-admin-<run slug>` answer, and they keep serving until deleted with `pw endpoints delete`. |
| By hand | `pw workflows run --trust -i inputs.json /abs/path/workflows/probe/yamls/general_run_tests.yaml` from a checkout of `parallelworks/workflows`; the inputs name this repository and branch under `tests`. |

Both actions authenticate with the repository secret `ACTIVATE_PARALLEL_WORKS`, a
platform API key; the dashboard action also passes it to the dashboards, which use it
after their run completes. Each action takes the branch, tag or commit of
`parallelworks/workflows` to take the PROBE workflow from (`workflows_ref`, default
`canary`), the resource the tests or dashboards run on, and the results bucket and path.
Both are manual; a `schedule` trigger can be added to `run-tests.yml` to run the suite
periodically.

Results are uploaded to the bucket as each test finishes. Open the dashboard and press
`Refresh` to see them.

## Add, edit or remove a test

Tests are files, so every change is a git change here:

1. **Add**: copy a file from `tests/`, give it a new `name`, change the target and the
   inputs (the form payload of the workflow). Keep `timeout_s` above the cold-install
   time of the workflow on that system.
2. **Edit**: change the JSON file (inputs, `timeout_s`, ...).
3. **Remove**: delete the JSON file.
4. Check the definitions with `python3 -m probe list --tests tests` from
   `workflows/probe/app` of a `parallelworks/workflows` checkout, commit and push.
5. Press `Refresh` on the dashboard. It re-fetches the definitions, so the change
   shows at once. A run of the tests fetches them anyway.
6. After a removal the test's history is still in the bucket, so the dashboard keeps
   showing it as a test without a definition. Open it on the admin dashboard and press
   `Delete results` to drop that history too (or `pw buckets rm -r <bucket>/<path>/<id>/`).

Renaming a test (a new `name`) is a removal plus an addition: the history stays under
the old id until you delete it.

Most tests here were imported from the end-to-end tests recorded in
`parallelworks/workflows` under `workflows/<name>/tests/general/`, with
`workflows/probe/scripts/import_workflow_tests.py`; the import overwrites files of the
same name, so change or remove such a test there as well:

```bash
cd /path/to/workflows
python3 workflows/probe/scripts/import_workflow_tests.py . --variant general \
    --platform activate.parallel.works --user alvaro --out /path/to/probe-tests-activate-parallel-works/tests
```

## Test definition

```json
{
  "name": "gcp-controller",
  "platform": "activate.parallel.works",
  "user": "alvaro",
  "workflow_name": "webshell",
  "workflow": {
    "repo": "github.com/parallelworks/workflows",
    "path": "workflows/webshell/yamls/general.yaml",
    "ref": "canary"
  },
  "timeout_s": 1200,
  "warm_marker": "${HOME}/pw/software/noVNC-1.3.0/ttyd.x86_64",
  "leftover_patterns": ["ttyd", "pw endpoints run"],
  "inputs": {
    "cluster": { "resource": "pw://alvaro/gcpsmall", "scheduler": false },
    "service": {}
  }
}
```

| Field | Meaning |
|---|---|
| `name` | Test name, unique within its platform, user and workflow. |
| `platform`, `user` | Platform host and user that run the test. |
| `workflow_name` | Groups the tests of one workflow, for example its directory name. |
| `workflow.repo`, `.path`, `.ref` | Repository (host and path, or a git URL), path of the workflow YAML, and branch, tag or commit. A branch follows development; a tag or commit pins a release. |
| `timeout_s` | Seconds to wait for the run, default 1800. On timeout the run is canceled and the test fails. |
| `inputs` | Passed verbatim to `pw workflows run -i`. |
| `warm_marker` | Optional. Path, or list of paths, on the target system. All present before launch: phase `warm`; none: `cold`; some: `partial`. |
| `leftover_patterns` | Optional. Process command-line patterns that must be gone from the target system after cleanup; compute tests also require an empty scheduler queue. |
| `leftover_commands` | Optional. `{name: shell snippet}`; each snippet runs on the target after cleanup and must print `0`. |
| `setup` | Optional. Shell snippet run on the target before the launch. Must be safe to repeat. |

Two files with the same id, or an unknown key, are errors. Only workflows that run to
completion can be tested: the workflow fails its run when its service is not healthy
and completes once it is, and PROBE trusts the run status. What PROBE does with a test,
and the format of the records it writes, are documented in the
[PROBE README](https://github.com/parallelworks/workflows/blob/canary/workflows/probe/README.md).
