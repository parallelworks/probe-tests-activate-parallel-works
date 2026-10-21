# MPI hello world

The smallest test that a cluster's MPI works through the ACTIVATE platform: a C
program is compiled with the cluster's `mpicc`, run as one SLURM or PBS job across
two nodes (or on the login node as a quick check), and the run passes only when
every rank reported, the ranks ran on as many nodes as requested, and a collective
(`MPI_Allreduce`) between them gave the right answer. Nothing is installed, no
endpoint is registered, nothing is left behind.

It is an HSP (`activate.hpc.mil`) workflow: the job goes through the `hsp` script
submitter of [parallelworks/workflows](https://github.com/parallelworks/workflows)
and the form carries the SLURM account, QoS and DSRC node type that on-prem systems
need. On a cloud cluster of another platform it behaves like a `general` workflow.
The first system it targets is Nautilus (`pw://avidalto/nautilus`, SLURM, Navy DSRC).

```
yamls/hsp.yaml               the workflow (self-contained: the run checks nothing out of its own)
tests/hsp/*.json             its inputs, in the format of the workflows repository's test runner
scripts/nautilus-check.sh    the manual check to run on the Nautilus login node before the first run
../../../tests/activate.hpc.mil/avidalto/mpi-hello/*.json   the same inputs as PROBE definitions
```

## The jobs

1. **preprocessing** (login node): writes `inputs.sh`, then `mpi-env.sh` from the
   form's MPI environment commands (with `module` initialized first, since a
   workflow step is not a login shell) and fails the run if sourcing it in a fresh
   shell does not provide `mpicc` and the launcher; compiles `mpi_hello.c`; writes
   `mpi-hello.sh`, the job script.
2. **mpi_job**: the `script_submitter/v3.6/hsp.yaml` subworkflow runs `mpi-hello.sh`
   in the run's job directory, submitted with `sbatch`/`qsub` (`--nodes` x
   `--ntasks-per-node` from the form) or on the login node, and streams
   `run.<id>.out` into the run log. The script records its exit status in
   `mpi-hello.exit` (the submitter never forwards it) and the program's output in
   `mpi-hello.out`.
3. **Check the Results** (same job): fails the run when the exit file is missing
   (the script never ran to its end: killed, walltime, node failure) or non-zero,
   when fewer ranks than nodes x ranks per node said hello, when the Allreduce line
   is not `OK`, or when a multi-node job put every rank on one node. Publishes
   `RANKS`, `HOSTS` and `MPI_OUTPUT`.

The YAML is self-contained: the C source and both scripts are written by
preprocessing from heredocs in the YAML, so the run checks nothing out of this
repository. Only the script submitter is fetched from GitHub (`canary`).

## Inputs

| Input | Meaning |
|---|---|
| Compute resource | The cluster. The program is compiled on its login node and run on its compute nodes. |
| Submit to the scheduler | Off runs the ranks on the login node (seconds, a quick check). |
| Nodes, MPI ranks per node | The job's shape. With 2 or more nodes the check also requires the ranks to have run on 2 or more hosts. |
| SLURM directives | Account, partition, QoS, node type (`--constraint`), walltime, extra `#SBATCH` lines. Account, QoS and node type apply to on-prem (`existing`) resources. |
| PBS directives | Account and extra `#PBS` lines for the PBS systems. |
| MPI environment commands | Empty takes the MPI on PATH, else the first known module that loads (`mpi/latest`, `mpich/gnu`, `mpi/mpich-x86_64`, `mpi/openmpi-x86_64`, `openmpi`, `mpich`); otherwise the commands that put `mpicc` and the launcher on PATH. Run on the login node to compile and inside the job. |
| MPI launcher | The command up to its process-count option: `mpirun -np` (default), `srun --mpi=pmi2 -n`, `srun -n`. The job runs `<launcher> <ranks> mpi_hello`. |

## Other systems

Nothing in the workflow is specific to Nautilus but the defaults of its tests: the
MPI comes from the environment commands, or from the known modules when they are
left empty, and the launcher from its input.

| System | MPI | Environment commands |
|---|---|---|
| Nautilus (Navy DSRC) | MPICH 3.3.2, `mpich/gnu/3.3.2` (also `mpich/intel`, `mpich/aocc`) | `module load mpich/gnu/3.3.2`, or empty (`mpich/gnu` is a known module) |
| FRAN | Intel MPI 2021.14, `mpi/2021.14` and `mpi/latest` | `module load mpi/latest`, or empty |
| awshpc (AWS cluster of activate.parallel.works) | Amazon Open MPI on PATH (`/opt/amazon/openmpi`); MPICH 4.1.1 as `mpi/mpich-x86_64` | empty (takes the Open MPI on PATH), or `module load mpi/mpich-x86_64` |
| gcpsmall (Google cluster of activate.parallel.works) | Open MPI 4.1 as `mpi/openmpi-x86_64`, MPICH as `mpi/mpich-x86_64` | `module load mpi/openmpi-x86_64`, or empty |

MPICH's and Intel MPI's `mpirun` (Hydra) and Open MPI's all read the SLURM or PBS
allocation, so `mpirun -np` is the default launcher everywhere; `srun --mpi=pmi2 -n`
is the alternative where a site's MPI is built for it. On a cloud cluster the hsp
submitter writes no account, QoS, CPUs-per-task, node-count or constraint header
(those are for on-prem `existing` resources) and the job's shape comes from the
`--nodes` and `--ntasks-per-node` directives the workflow composes, so the same YAML
runs there, which is how it is tested from activate.parallel.works.

## Check Nautilus by hand first

The workflow was written from what the workflows repository knows about Nautilus and
from its `module avail mpi` and `sinfo` listings, not from a run there. On the
Nautilus login node:

```bash
bash scripts/nautilus-check.sh
```

prints the facts the workflow relies on (`module` in a non-login shell, the
`mpich/gnu/3.3.2` module, the accounts and QoS the user can submit with, the node
features behind `--constraint`, whether `pw` and GitHub are reachable from the login
node) and compiles and runs the hello world on the login node with `mpirun -np 2`.
Then, with the account the output lists:

```bash
bash scripts/nautilus-check.sh --account <account> --qos standard --constraint standard
```

submits one 2-node SLURM job that runs the program with `mpirun`, `srun --mpi=pmi2`
and `srun`, waits up to 20 minutes for it and prints its output. The two outputs
decide the test inputs: the account and QoS, whether `standard` is a valid constraint,
and which launcher `mpi.launcher` should default to.

## Running from the CLI

With `pw` authenticated against the HSP platform:

```bash
cd /abs/path/probe-tests-activate-parallel-works/workflows/activate.hpc.mil/mpi-hello
# validate the YAML and the submitter call without running anything
pw workflows run --dry-run "${PWD}/yamls/hsp.yaml" -i '{"resource":"pw://avidalto/nautilus","cluster":{"scheduler":false,"ntasks_per_node":2},"mpi":{"load":"module load mpich/gnu/3.3.2","launcher":"mpirun -np"}}'
# the login-node check
pw workflows run "${PWD}/yamls/hsp.yaml" -i '{"resource":"pw://avidalto/nautilus","cluster":{"scheduler":false,"ntasks_per_node":2},"mpi":{"load":"module load mpich/gnu/3.3.2","launcher":"mpirun -np"}}'
# two nodes, two ranks each: the inputs of tests/hsp/nautilus-compute.json without its _test object
pw workflows run "${PWD}/yamls/hsp.yaml" -i "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d.pop("_test", None); print(json.dumps(d))' tests/hsp/nautilus-compute.json)"
```

The account and QoS of an on-prem system have no default: pass them in a CLI run
(an empty `--qos=` makes `sbatch` reject the job). From the platform's UI, run the
YAML as a file or register it as a workflow; the form lists the account and QoS
from the resource.

A run passes when it reaches `completed`; its `Check the Results` step prints the
ranks' output and a notice with the rank and node counts. A failed run says why in
`pw workflows runs errors <slug>`.

## Output and debugging

Everything is in the run's job directory on the login node (`~/pw/jobs/<run-slug>/`
for CLI runs, `~/pw/jobs/<workflow-name>/<run-number>/` for registered ones):

```
inputs.sh        the form values the scripts saw
mpi-env.sh       the MPI environment file
mpi_hello.c      the program, and mpi_hello, its binary
mpi-hello.sh     the job script; run.sh is the submitter's assembled sbatch/qsub script
run.<id>.out     the job's stdout and stderr
mpi-hello.out    the program's output alone
mpi-hello.exit   the job script's exit status
logs/<job>/step_N/step.out   the step traces (::error lines say why a run failed)
```

From anywhere: `pw workflows runs errors <slug>` and `pw workflows runs logs <slug>`.

## Tests

`tests/hsp/nautilus-compute.json` (two nodes, two ranks per node, through SLURM)
and `tests/hsp/nautilus-login.json` (two ranks on the login node) are the inputs
in the format of the workflows repository's test runner (`_test` is stripped before
launch). The same inputs, as PROBE definitions, are
`tests/activate.hpc.mil/avidalto/mpi-hello/nautilus-compute.json` and
`nautilus-login.json` at the root of this repository; they point `workflow.repo` at
this repository and `workflow.ref` at the `hsp` branch.

`tests/hsp/awshpc-login.json` (the environment commands left empty: the Amazon
Open MPI already on PATH is used) and `tests/hsp/awshpc-compute.json` (two cloud
nodes, `module load mpi/mpich-x86_64`, MPICH 4.1.1) run the same workflow on
`pw://alvaro/awshpc` of activate.parallel.works; their PROBE definitions are under
`tests/activate.parallel.works/alvaro/mpi-hello/`. They are how the workflow is tested
end to end before a run on HSP, from a `parallelworks/workflows` checkout, and both
passed on 2026-10-21 (runs `fancy-platypus`, 40 s, and `national-slug`, 291 s with the
cloud nodes' boot; two ranks on each of two nodes, Allreduce correct, no leftovers):

```bash
cd workflows/probe/app
python3 -m probe run --tests /path/to/probe-tests-activate-parallel-works/tests --results results \
    --test activate.parallel.works/alvaro/mpi-hello/awshpc-login.json
```

The account in them (`hpcmo49636prw`) is the one the `rag-vllm` Nautilus test of
the workflows repository used in September 2026; `scripts/nautilus-check.sh` prints
the accounts and QoS the user can submit with, to confirm it before the first run.
