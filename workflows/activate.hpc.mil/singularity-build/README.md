# Singularity build

Builds a Singularity image (`.sif`) from a definition file on the login node of a
cluster, the way an HPC user builds the container a job will run: the definition
pasted in the form is written to the job directory, the runtime (Apptainer or
SingularityCE) is located, `build` runs with the layer cache and scratch under a
directory of the user's choosing, and a command is run inside the finished image to
prove it mounts and runs on that node. The run completes with the image's path and
fails loud at the first missing piece: no runtime, a registry the login node cannot
reach, a `%post` that fails, a `%test` that fails, an image that does not run. Nothing
is submitted to the scheduler, no endpoint is registered, and nothing is left behind
but the image and its cache.

It is an HSP (`activate.hpc.mil`) workflow: it initializes `module` and adds the
HPCMP module directories itself (a workflow step is not a login shell), and the form's
environment commands take `module load singularity` or a proxy export where a system
needs one. It runs on the login node only and submits nothing, so the same file runs
unchanged on a cloud cluster of another platform, which is how it is tested from
activate.parallel.works.

`yamls/hsp.yaml` is the whole workflow: every script is written by its steps from
heredocs, so a run checks nothing out of this repository and fetches nothing from
GitHub. The tests that launch it are the PROBE definitions under
`tests/<platform>/<user>/singularity-build/` at the root of this repository (Tests,
below); nothing in this directory names a user or a system's credentials.

## The steps

One job, `build`, on the login node:

1. **Create Inputs**: writes `inputs.sh` with the form values and the `PW_*`
   environment, applies the form's defaults to the values a CLI run left empty,
   appends `.sif` to the image name when missing, checks the name and the paths,
   and writes the test command and the extra build options to files (they may
   hold quotes).
2. **Prepare the Container Runtime**: writes `runtime-env.sh` (`module` initialized
   first, the HPCMP directories `/p/app/modulefiles` and `/p/app/site/modulefiles`
   added when they exist) from the form's environment commands, or, when they are
   empty, from the `apptainer` or `singularity` already on PATH or the first of the
   modules `apptainer`, `singularity` and `singularity-ce` that loads. Fails the run
   when a fresh shell that sources the file has no runtime. Then prints what an
   unprivileged build depends on: the runtime version, the user's `subuid` range,
   the user namespace limit, the `allow setuid` setting, the proxy variables, `HOME`,
   `WORKDIR` and `TMPDIR`, and the free space of the image directory.
3. **Write the Definition File**: `container.def` from the form; fails when it is
   empty or has no `Bootstrap:` line.
4. **Build the Image**: `<runtime> build --force [--fakeroot] [options] <partial>
   container.def` under `timeout`, with `APPTAINER_CACHEDIR`/`SINGULARITY_CACHEDIR`
   set to the cache directory and the build's `TMPDIR` to `tmp` under it (login nodes
   keep `/tmp` small). The image is built under a temporary name
   (`.<image>.<run slug>.partial`) in the image directory and renamed once complete,
   so a failed or cancelled build never leaves a half-written file under the final
   name; the trap removes the temporary file. The `%test` section of the definition
   runs inside the build and fails it when it fails. On success the step prints
   `inspect`'s labels and publishes `IMAGE`, `IMAGE_SIZE`, `BUILD_SECONDS` and
   `RUNTIME`.
5. **Test the Image**: `<runtime> exec <image> /bin/sh -c '<test command>'` under a
   10-minute timeout; a non-zero exit fails the run. An empty command skips the step
   with a notice. Publishes `TEST_OUTPUT`.

## Inputs

| Input | Meaning |
|---|---|
| Compute resource | The cluster. The image is built on its login node, which needs the runtime and access to the registry the definition bootstraps from. |
| Definition file | What `singularity build` reads: a `Bootstrap:` line and the sections the image needs. The default builds `python:3.12-slim` with NumPy and tests the import. |
| Image file name | Written into the image directory; `.sif` appended when missing; an existing image of that name is replaced. |
| Image directory | Absolute path, created when missing, expanded by the shell (`${HOME}`, `${WORKDIR}`). Default `${HOME}/pw/software/containers`; on a DSRC system point it at `$WORKDIR` or a project directory. |
| Test command | Run inside the built image through `/bin/sh -c` after the build; empty skips it. Default `cat /etc/os-release`. |
| Build with --fakeroot | Off lets the runtime choose how to emulate root in `%post`; on passes `--fakeroot`, which maps the user's `subuid` range and is what SingularityCE needs for a `%post` that installs packages. |
| Build time limit | Minutes; the build is killed and the run fails when it is exceeded. Default 60. |
| Extra build options | Appended to the build command: `--notest`, `--disable-cache`, Apptainer's `--ignore-subuid --ignore-fakeroot-command` (no root emulation at all). |
| Environment commands | Empty takes the runtime on PATH, else the first known module; otherwise the commands that provide one or set a proxy, one per line, run before every step. |
| Cache directory | Layer cache and build scratch. Empty: `.cache` under the image directory. |

## Root emulation

An unprivileged `build` has to run the `%post` section as something that can write the
image's root filesystem, and the runtimes differ:

- **Apptainer** (1.1 and later) builds unprivileged by default: with a `subuid` range
  for the user it maps that range (`--fakeroot`); without one it tries the `fakeroot`
  command, then a single-user root-mapped namespace. On gcpsmall (Apptainer 1.4.5,
  `subuid` configured) `pip install`, `dnf install` and `gcc` in `%post` all build with
  the box off, with it on, and even with `--ignore-subuid --ignore-fakeroot-command`
  (verified 2026-10-21).
- **SingularityCE** needs `--fakeroot` (a `subuid` range the site configured) for a
  `%post` that acts as root, or `proot` on PATH (4.1 and later) for a rootless build.
  The Prepare step prints the `subuid` range so a `--fakeroot` failure can be read
  against it.

## Other systems

Nothing in the workflow is specific to one system: the runtime comes from the
environment commands, or from PATH and the known modules when they are left empty.

| System | Runtime | Environment commands | Verified |
|---|---|---|---|
| gcpsmall (Google cluster of activate.parallel.works) | Apptainer 1.4.5 on PATH, `subuid` configured, no proxy | empty | 2026-10-21, all three test definitions |
| Nautilus (Navy DSRC) | to be recorded from the first run | | |
| FRAN (ARL DSRC) | to be recorded from the first run | | |
| awssmall (AWS cluster of activate.hpc.mil) | to be recorded from the first run | | |

## Running it

From the platform, register the YAML or run it as a file and fill the form, or paste
an inputs JSON. The `inputs` object of a PROBE definition is one; the shape is:

```json
{
  "resource": "pw://<user>/<cluster>",
  "container": {
    "definition": "Bootstrap: docker\nFrom: python:3.12-slim\n\n%post\n    pip install --no-cache-dir numpy==2.3.3\n",
    "image_name": "python-numpy.sif",
    "output_dir": "${HOME}/pw/software/containers",
    "test_command": "python -c \"import numpy; print(numpy.__version__)\""
  },
  "build": {
    "fakeroot": false,
    "timeout_min": 30,
    "options": "",
    "environment": "",
    "cache_dir": ""
  }
}
```

From a shell with `pw` authenticated against the platform:

```bash
pw workflows run --dry-run /abs/path/yamls/hsp.yaml -i inputs.json   # validates, runs nothing
pw workflows run /abs/path/yamls/hsp.yaml -i inputs.json
```

A run passes when it reaches `completed`; its Build step prints a notice with the
image's path and size, its Test step one with the test command's first line and how
to run the image. A failed run says why in `pw workflows runs errors <slug>`.

## Output and debugging

Everything is in the run's job directory on the login node (`~/pw/jobs/<run-slug>/`
for CLI runs, `~/pw/jobs/<workflow-name>/<run-number>/` for registered ones):

```
inputs.sh          the form values the steps saw, resolved (paths expanded, defaults applied)
runtime-env.sh     the runtime environment file every step sources
container.def      the definition the image was built from
build.log          the build's output
test-command.txt   the test command, test.out its output
logs/build/step_N/step.out   the step traces (::error lines say why a run failed)
```

The image is at `<image directory>/<image file name>`, the cache at
`<cache directory>` (`cache/` holds the OCI layers, `tmp/` the build scratch, empty
after a build). From anywhere: `pw workflows runs errors <slug>` and
`pw workflows runs logs <slug>`.

## Troubleshooting

A failing run is first of all a finding about the cluster, which is what a PROBE test
is for: a test keeps the definition and options its inputs were submitted with, and a
working alternative is a second test, not a change to the first.

- **`No container runtime found`** in Prepare: nothing on PATH and none of the known
  modules loads in a workflow step. Put the site's command in the environment
  commands (`module load singularity/<version>`; `module avail singularity` in a
  login shell lists the name). A module directory a login-only profile adds goes in
  as `module use <directory>` before the `module load`.
- **`Fetching OCI image` fails, or the build sits there until the time limit**: the
  login node does not reach the registry. On a system that reaches the internet
  through a proxy, export it in the environment commands (`export
  https_proxy=... http_proxy=... no_proxy=...`); a workflow step does not run the
  login profile that sets it. Bootstrap from an image already on the system
  (`Bootstrap: localimage`) when the node has no route out at all.
- **`%post` fails on a permission or a `chown`**, or `--fakeroot` fails with no
  `subuid` mapping: read the `subuid range` and `user namespaces` lines of Prepare.
  With Apptainer, try the box off (its own cascade) or
  `--ignore-subuid --ignore-fakeroot-command` in the options; with SingularityCE ask
  the site for a `subuid` range, or install `proot`.
- **`No space left on device` during the build**: the cache directory's filesystem is
  full (the build unpacks the whole image under `tmp/`). Set the cache directory, or
  the image directory it defaults under, to a filesystem with room.
- **`failed to execute %test script`**: the definition's own test failed inside the
  build, so the image was not written. Fix the definition, or pass `--notest` to
  look at the image anyway.
- **The build passes and the Test step fails**: the finished image does not run on
  the login node the way the build's sandbox did (a missing `/bin/sh`, a command not
  on the image's PATH, a node that cannot mount a SIF). The output above the error
  says which.

## Tests

A test is named after the cluster, `login`, the definition and the root emulation it
was submitted with: `<cluster>-login-<definition>-<auto|fakeroot|norootemulation>`.
The definitions live under `tests/<platform>/<user>/singularity-build/` at the root
of this repository, point `workflow.repo` at this repository and `workflow.ref` at the
branch the workflow is on (`hsp-tests-singularity` while it is developed there), and
carry the exact inputs that were submitted on the platform: a test is added only from
such a submission, never from assumed values. Their results are PROBE's records, in
its results bucket and on its dashboard. `warm_marker` is the layer cache: a `warm`
run skipped the download, a `cold` one fetched the base image.

The definitions the tests build, each a few minutes at most on a warm cache:

| Definition | What it checks |
|---|---|
| `python-numpy` (the form's default) | `pip install` in `%post` from `python:3.12-slim`, a `%test` import, the test command run in the finished image |
| `rocky9-gcc` | `dnf install gcc` and a compile in `%post` from `rockylinux:9`: a `%post` that acts as root, submitted with `--fakeroot` |
| `alpine` | the smallest build, submitted with Apptainer's `--ignore-subuid --ignore-fakeroot-command`: no root emulation at all |

The gcpsmall tests (`gcpsmall-login-*`) are how the workflow is tested from the cloud
before a run on HSP; all three passed through `python3 -m probe run` on 2026-10-21.
