# MPI hello world

Check that a cluster's MPI works. The workflow compiles a small C program with the
cluster's `mpicc`, runs it as one job across nodes, and passes only when every rank
answered, the ranks spread over the nodes, and they could talk to each other.

```
  login node                              compute nodes: one SLURM or PBS job
  ──────────────────────────────          ─────────────────────────────────────
  1  load MPI    module load / PATH
  2  compile     mpicc mpi_hello.c  ──►   3  <launcher> <ranks> mpi_hello
                                             node A: rank 0, rank 1    "Hello"
                                             node B: rank 2, rank 3    "Hello"
                                             MPI_Allreduce over all ranks
  4  check   ◄─────────────────────────      every rank said hello
                                             ranks on 2 or more nodes
                                             the Allreduce is right
```

With the scheduler off, the ranks run on the login node instead, a quick check in
seconds. Nothing is installed, and nothing is left running.

## Run it

Run `yamls/hsp.yaml` on the platform and fill the form, or pass inputs like these:

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

```bash
pw workflows run /abs/path/yamls/hsp.yaml -i inputs.json
```

## The inputs that matter

| Input | Set it to |
|---|---|
| Submit to the scheduler | Off for the quick check on the login node. |
| Nodes, MPI ranks per node | The job's shape. Two nodes or more also tests the network between them. |
| SLURM account, partition, QoS | Your allocation. DSRC systems require them, and they have no default. |
| MPI environment commands | What provides `mpicc`, such as `module load mpich/gnu/3.3.2`. Empty tries the MPI on PATH, then common modules. |
| MPI launcher | `mpirun -np`, the default, or `srun --mpi=pmi2 -n` to let SLURM start the ranks. |

## What each system needs

| System | MPI environment commands | Launcher |
|---|---|---|
| Nautilus | `module load mpich/gnu/3.3.2`, or empty | `srun --mpi=pmi2 -n` |
| FRAN | `module load mpi/latest`, or empty; partition `standard` | `mpirun -np` |
| awshpc | Empty, which takes the Open MPI on PATH | `mpirun -np` |
| gcpsmall | `module load mpi/openmpi-x86_64`, or empty | `mpirun -np` |

On Nautilus, `mpirun` with `mpich/intel/3.3.2` cannot connect its processes between
nodes. `srun` avoids the problem.

## When it fails

The run's error names the cause (`pw workflows runs errors <slug>`).

| Error | Meaning | What to do |
|---|---|---|
| No MPI found | Nothing on PATH or in the common modules provides `mpicc` | Put the site's `module load` in MPI environment commands |
| Unable to locate a modulefile | The module's directory is only on a login shell's module path | Add `module use <directory>` before the `module load` |
| `HYDU_sock_connect ... Connection refused`, then a timeout | `mpirun` cannot connect its processes between nodes | Use `srun --mpi=pmi2 -n` |
| world size of 1 where N were launched | `srun` started the ranks without a process management interface (PMI) they understand | Intel MPI: `export I_MPI_PMI_LIBRARY=/usr/lib64/libpmi2.so`. MPICH: `--mpi=pmi2` |
| No exit status | The job was killed by its walltime, a node failure or a cancel | Read `run.<id>.out` in the job directory |

A test that fails this way is a finding about the system. Keep it, and record the
working alternative as a second test.

## Tests

The tests are PROBE definitions in this repository, under
`tests/<platform>/<user>/mpi-hello/`. Each is one JSON of inputs, with a `.md` that
says what it checks, named `<cluster>-<partition>-<N>nodes-<module>`. The launcher is
appended when it is not `mpirun`, and a login-node test uses `login` as the partition.

How each job works, the per-node diagnostics, the job directory's files and the full
troubleshooting are in [DEVELOPER.md](DEVELOPER.md).
