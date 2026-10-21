# MPI hello world

The smallest test that a cluster's MPI works through the ACTIVATE platform: a C
program is compiled with the cluster's `mpicc`, run as one SLURM or PBS job across
two nodes (or on the login node as a quick check), and the run passes only when
every rank reported, the ranks ran on as many nodes as the job had, and a collective
(`MPI_Allreduce`) between them gave the right answer. Nothing is installed, no
endpoint is registered, nothing is left behind.

It is an HSP (`activate.hpc.mil`) workflow: the job goes through the `hsp` script
submitter of [parallelworks/workflows](https://github.com/parallelworks/workflows)
and the form carries the SLURM account, QoS and DSRC node type that on-prem systems
need. On a cloud cluster of another platform it behaves like a `general` workflow.

`yamls/hsp.yaml` is the whole workflow: the C source and the scripts are written by
preprocessing from heredocs in it, so a run checks nothing out of this repository and
only the script submitter is fetched from GitHub (`canary`). The tests that launch it
are the PROBE definitions under `tests/<platform>/<user>/mpi-hello/` at the root of
this repository (Tests, below); nothing in this directory names a user, an account or
a system's credentials.

## The jobs

1. **preprocessing** (login node): writes `inputs.sh`, then `mpi-env.sh` (with
   `module` initialized first, since a workflow step is not a login shell) from the
   form's MPI environment commands, or, when they are empty, from the MPI already on
   PATH or the first known module that loads; fails the run if sourcing it in a fresh
   shell does not provide `mpicc` and the launcher; compiles `mpi_hello.c`; writes
   `mpi-hello.sh`, the job script, and `node-info.sh`.
2. **mpi_job**: the `script_submitter/v3.6/hsp.yaml` subworkflow runs `mpi-hello.sh`
   in the run's job directory, submitted with `sbatch`/`qsub` (`--nodes` x
   `--ntasks-per-node` from the form) or on the login node, and streams
   `run.<id>.out` into the run log. The script prints the host, the MPI, the rank
   layout it resolved from the allocation and, under SLURM, the PMI plugins `srun`
   offers and each node's addresses; then it runs `<launcher> <ranks> mpi_hello`
   under a 5-minute timeout. It records its exit status in `mpi-hello.exit` (the
   submitter never forwards it), the layout in `mpi-hello.layout` and the program's
   output in `mpi-hello.out`.
3. **Check the Results** (same job): fails the run when the exit file is missing
   (the script never ran to its end: killed, walltime, node failure), says `124`
   (the launch timed out) or is otherwise non-zero; when fewer ranks than the layout
   launched said hello; when the ranks did not all report that many processors with
   distinct rank numbers (a launcher that cannot hand the ranks their PMI starts N
   single-rank programs, each with a correct Allreduce of its own); when the
   Allreduce line is not `OK`; or when a multi-node job put every rank on one node.
   Warns when a scheduler directive changed the layout from the form's nodes x ranks
   per node. Publishes `RANKS`, `HOSTS` and `MPI_OUTPUT`.

## Inputs

| Input | Meaning |
|---|---|
| Compute resource | The cluster. The program is compiled on its login node and run on its compute nodes. |
| Submit to the scheduler | Off runs the ranks on the login node (seconds, a quick check). |
| Nodes, MPI ranks per node | The job's shape. With 2 or more nodes the check also requires the ranks to have run on 2 or more hosts. |
| SLURM directives | Account, partition, QoS, node type (`--constraint`), walltime, extra `#SBATCH` lines. Account, QoS and node type apply to on-prem (`existing`) resources. An empty walltime leaves the partition's default. |
| PBS directives | Account and extra `#PBS` lines for the PBS systems. |
| MPI environment commands | Empty takes the MPI on PATH, else the first known module that loads (`mpi/latest`, `mpich/gnu`, `mpi/mpich-x86_64`, `mpi/openmpi-x86_64`, `openmpi`, `mpich`); otherwise the commands that put `mpicc` and the launcher on PATH. Run on the login node to compile and inside the job. |
| MPI launcher | The command up to its process-count option: `mpirun -np` (default), `srun --mpi=pmi2 -n`, `srun -n`. The job runs `<launcher> <ranks> mpi_hello`. |

## Other systems

Nothing in the workflow is specific to one system: the MPI comes from the
environment commands, or from the known modules when they are left empty, and the
launcher from its input.

| System | MPI | Environment commands |
|---|---|---|
| Nautilus (Navy DSRC) | MPICH 3.3.2 as `mpich/gnu/3.3.2`, `mpich/intel/3.3.2`, `mpich/aocc/3.3.2` | `module load mpich/intel/3.3.2`, or empty (`mpich/gnu` is a known module) |
| FRAN | Intel MPI 2021.14 as `mpi/2021.14` and `mpi/latest` | `module load mpi/latest`, or empty |
| awshpc (AWS cluster of activate.parallel.works) | Amazon Open MPI on PATH (`/opt/amazon/openmpi`); MPICH 4.1.1 as `mpi/mpich-x86_64` | empty (takes the Open MPI on PATH), or `module load mpi/mpich-x86_64` |
| gcpsmall (Google cluster of activate.parallel.works) | Open MPI 4.1 as `mpi/openmpi-x86_64`, MPICH as `mpi/mpich-x86_64` | `module load mpi/openmpi-x86_64`, or empty |

MPICH's and Intel MPI's `mpirun` (Hydra) and Open MPI's all read the SLURM or PBS
allocation, so `mpirun -np` is the default launcher everywhere; `srun --mpi=pmi2 -n`
is the alternative where a site's MPI is built for it. On a cloud cluster the hsp
submitter writes no account, QoS, CPUs-per-task, node-count or constraint header
(those are for on-prem `existing` resources) and the job's shape comes from the
`--nodes` and `--ntasks-per-node` directives the workflow composes, so the same YAML
runs there, which is how it is tested from activate.parallel.works.

## Running it

From the platform, register the YAML or run it as a file and fill the form, or paste
an inputs JSON. The `inputs` object of a PROBE definition is one; the shape is:

```json
{
  "resource": "pw://<user>/<cluster>",
  "cluster": {
    "scheduler": true,
    "nodes": 2,
    "ntasks_per_node": 2,
    "slurm": {
      "is_enabled": true,
      "account": "<account>",
      "partition": "<partition>",
      "qos": "<qos>",
      "node_type": "",
      "time": "00:10:00",
      "scheduler_directives": ""
    }
  },
  "mpi": {
    "load": "module load <mpi module>",
    "launcher": "mpirun -np"
  }
}
```

From a shell with `pw` authenticated against the platform:

```bash
pw workflows run --dry-run /abs/path/yamls/hsp.yaml -i inputs.json   # validates, runs nothing
pw workflows run /abs/path/yamls/hsp.yaml -i inputs.json
```

The account and QoS of an on-prem system have no default: pass them (an empty
`--qos=` makes `sbatch` reject the job). A run passes when it reaches `completed`;
its `Check the Results` step prints the ranks' output and a notice with the rank and
node counts. A failed run says why in `pw workflows runs errors <slug>`.

## Output and debugging

Everything is in the run's job directory on the login node (`~/pw/jobs/<run-slug>/`
for CLI runs, `~/pw/jobs/<workflow-name>/<run-number>/` for registered ones):

```
inputs.sh        the form values the scripts saw
mpi-env.sh       the MPI environment file
mpi_hello.c      the program, and mpi_hello, its binary
mpi-hello.sh     the job script; run.sh is the submitter's assembled sbatch/qsub script
node-info.sh     the per-node address report the job script runs under SLURM
run.<id>.out     the job's stdout and stderr: the header lines, the launcher's messages, the ranks' output
mpi-hello.out    the program's output alone
mpi-hello.layout the ranks and nodes the job launched
mpi-hello.exit   the job script's exit status
logs/<job>/step_N/step.out   the step traces (::error lines say why a run failed)
```

From anywhere: `pw workflows runs errors <slug>` and `pw workflows runs logs <slug>`.

## Troubleshooting

A failing run is first of all a finding about the cluster, which is what a PROBE
test is for: a test keeps the launcher and environment its inputs were submitted
with, and a working alternative is a second test, not a change to the first.

- **`HYDU_sock_connect ... unable to connect from <node 2> to <node 1> (Connection
  refused)`, then `srun: error: ... task 1: Exited with exit code 5`, then the launch
  times out after 5 minutes** (seen on Nautilus with `mpich/intel/3.3.2` and
  `mpirun -np`, 2026-10-21). MPICH's Hydra started its proxies with `srun`, but the
  proxy on the second node could not open a TCP connection to the one on the first
  node at the address its hostname resolves to (the `Nodes :` lines of the output
  show that address and the interfaces each node has). Alternatives: launch with
  SLURM, `srun --mpi=pmi2 -n` (SLURM starts the ranks and serves PMI, no Hydra
  sockets; the `PMI :` line lists the plugins `srun` offers), which passed on
  Nautilus the same day, or point Hydra at the interface the nodes reach each other
  on, `mpirun -iface <interface> -np`.
- **`The ranks reported a world size of 1 where N were launched`** with an `srun`
  launcher: the ranks started but found no PMI, so each ran alone. Intel MPI under
  `srun` needs SLURM's PMI library named in the environment commands, for example
  `export I_MPI_PMI_LIBRARY=/usr/lib64/libpmi2.so` after the `module load`; MPICH
  needs `--mpi=pmi2` on a SLURM whose default PMI is `none`.

## Tests

A test is named after the cluster, the partition (or `login`), the node count and
the MPI load command: `<cluster>-<partition>-<N>nodes-<module>`, with the launcher
appended when it is not the default. The definitions live under
`tests/<platform>/<user>/mpi-hello/` at the root of this repository, point
`workflow.repo` at this repository and `workflow.ref` at the `hsp` branch, and carry
the exact inputs that were submitted on the platform: a test is added only from such
a submission, never from assumed values. Their results are PROBE's records, in its
results bucket and on its dashboard.

The awshpc tests (`awshpc-login-1node-mpi-on-path`, `awshpc-compute-2nodes-mpich-x86_64`)
are how the workflow is tested from the cloud before a run on HSP; both passed through
`python3 -m probe run` on 2026-10-21.
