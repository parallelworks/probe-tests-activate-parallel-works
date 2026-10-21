# PROBE tests for activate.parallel.works

Test definitions for [PROBE](https://github.com/parallelworks/workflows/tree/canary/workflows/probe)
on the `activate.parallel.works` platform, one JSON file per test:

```
tests/<platform>/<user>/<workflow_name>/<name>.json
```

A test launches a workflow YAML from a git repository with fixed inputs on one system and
passes when the run completes. The fields are documented in the
[PROBE README](https://github.com/parallelworks/workflows/blob/canary/workflows/probe/README.md#test-definition).
PROBE fetches this repository at run time, so a pushed change is picked up by the next run
and by `Refresh` on the dashboard. Results go to `pw://alvaro/gcpbucket` under `probe/results`.

## Run the tests

- **Run PROBE tests** (GitHub action): runs all tests, or the files listed in `selection`,
  on the platform. Failed tests are listed in the job summary; the job fails only when the
  suite could not run.
- **Start PROBE dashboard** (GitHub action): starts the dashboards. `Run all` and
  `Rerun test` on the admin dashboard (`probe-admin-<run slug>`) launch tests. Stop the
  dashboards with `pw endpoints delete probe-<run slug>` and `probe-admin-<run slug>`.

Both actions run PROBE's workflows from `parallelworks/workflows` at `workflows_ref`
(default `canary`) with the tests of the branch they run from, on the `resource` given,
and authenticate with the repository secret `ACTIVATE_PARALLEL_WORKS`. They are manual;
a `schedule` trigger on `run-tests.yml` runs the suite periodically.

## Change the tests

Add a test by copying a file and giving it a new `name`; edit or delete the file for the
other changes. `python3 -m probe list --tests <path to tests/>`, run from `workflows/probe/app`
of a `parallelworks/workflows` checkout, validates the files. Commit, push, and press
`Refresh` on the dashboard. A removed test keeps its history in the bucket until
`Delete results` on the admin dashboard.

## HSP (activate.hpc.mil)

The tests for the HSP platform belong in its own GitLab repository; until that one is
reachable they live on this branch, beside the activate.parallel.works ones:

```
tests/activate.hpc.mil/<user>/<workflow_name>/<name>.json   the definitions
workflows/activate.hpc.mil/<workflow_name>/                  the workflows they launch: the YAML under yamls/, a README,
                                                             helper scripts
```

The definitions point `workflow.repo` at this repository and `workflow.ref` at the
branch the workflow is on, so PROBE fetches the YAML from here. PROBE runs only the
definitions whose `platform` and `user` match the `pw` context it runs under, so the
GitHub actions above, which authenticate on activate.parallel.works, never run these:
start PROBE's `general_run_tests.yaml` or `general.yaml` from the HSP platform (the user
workspace or a login node with the `pw` CLI, `python3` and `git`) with `tests.repo` set
to this repository, `tests.branch` to the branch and `tests.directory` to `tests`.

| Workflow | What it checks | README |
|---|---|---|
| `mpi-hello` | the cluster's MPI, as a two-node SLURM or PBS job or on the login node | `workflows/activate.hpc.mil/mpi-hello/README.md` |
| `singularity-build` | an Apptainer or SingularityCE image built from a definition file on the login node, and run there | `workflows/activate.hpc.mil/singularity-build/README.md` |

Each workflow's README says how its tests are named and what each one submits. The
`singularity-build` definitions are on the `hsp-tests-singularity` branch, which their
`workflow.ref` names, until they merge.
