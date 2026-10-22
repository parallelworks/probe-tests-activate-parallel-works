# Singularity build

Builds a Singularity image (`.sif`) from a definition file on the login node of a
cluster, the way an HPC user builds the container a job will run: the definition
pasted in the form is written to the job directory, the runtime (Apptainer or
SingularityCE) is located, `build` runs with the layer cache under a directory of
the user's choosing and its scratch on the node's local disk, and a command is run
inside the finished image to prove it mounts and runs on that node. The run completes with the image's path and
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
   empty, from the `apptainer` or `singularity` already on the step's PATH, else the
   first of `/usr/local/bin`, `/opt/apptainer/bin`, `/opt/singularity/bin`,
   `/usr/local/apptainer/bin` and `/usr/local/singularity/bin` that holds one, else
   the one the user's login shell finds (`bash -lc 'command -v apptainer'`, a path
   taken from whatever else the profile prints), else the first of the modules
   `apptainer`, `singularity` and `singularity-ce` that loads; a directory found this
   way is prepended to PATH in the file. A workflow step's PATH is shorter than a
   login shell's, and that is where FRAN and awssmall keep their runtime. Fails the
   run when a fresh shell that sources the file has no runtime. Then prints what an
   unprivileged build depends on: the runtime version, the user's `subuid` range,
   the user namespace limit, the `allow setuid` setting, the proxy variables, `HOME`,
   `WORKDIR` and `TMPDIR`, `proot`, whether the kernel has `squashfs` and
   `squashfuse` is there (what running a SIF needs), the node's CA bundle (copied to
   `site-ca-bundle.crt` in the job directory for `%files`, below), and the filesystem
   and free space of the image, cache and scratch directories. It warns before the
   build when the node cannot mount a SIF and the build is not a sandbox (A node
   that cannot mount a SIF, below). The build scratch is the form's directory or,
   when it is empty, the first of `TMPDIR`, `/tmp`, `/var/tmp` and `/dev/shm` that
   is writable, not mounted `noexec` and on a local filesystem (each option is listed
   with what disqualified it), with a warning when the one picked is `noexec` or a
   network filesystem (Root emulation, below).
3. **Write the Definition File**: `container.def` from the form; fails when it is
   empty or has no `Bootstrap:` line.
4. **Build the Image**: `<runtime> build --force [--fakeroot] [options] <partial>
   container.def` under `timeout`, with `APPTAINER_CACHEDIR`/`SINGULARITY_CACHEDIR`
   set to the cache directory and `APPTAINER_TMPDIR`/`SINGULARITY_TMPDIR` to the
   build scratch directory. The image is built under a temporary name
   (`.<image>.<run slug>.partial`) in the image directory and renamed once complete,
   so a failed or cancelled build never leaves a half-written file under the final
   name; the trap removes the temporary file, or directory for a `--sandbox` build.
   An existing image of that name is replaced, a SIF or a sandbox; a directory that
   is not a container sandbox (no `.singularity.d` in it) is never removed, and the
   run fails instead. The `%test` section of the definition
   runs inside the build and fails it when it fails. A build that failed fetching
   the base image, before `%post` ran, is tried up to three times, 30 s and 60 s
   apart (a connection dropped, reset or refused on the way to the registry, a
   rate limit); a missing tag, a denied pull or an unknown host fails at once.
   Each failed attempt's output is kept as `build.attempt<N>.log`. On success the step prints
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
| Image file name | Written into the image directory; `.sif` appended when missing, except for a `--sandbox` build, which writes a directory under the name as given; an existing image of that name is replaced. |
| Image directory | Absolute path, created when missing, expanded by the shell (`${HOME}`, `${WORKDIR}`). Default `${HOME}/pw/software/containers`; on a DSRC system point it at `$WORKDIR` or a project directory. |
| Test command | Run inside the built image through `/bin/sh -c` after the build; empty skips it. Default `cat /etc/os-release`. |
| Build with --fakeroot | Off lets Apptainer choose its root emulation and gives SingularityCE `--fakeroot` when the user has a `subuid` range; on always passes `--fakeroot`. |
| Build time limit | Minutes; the build is killed and the run fails when it is exceeded. Default 60. |
| Extra build options | Appended to the build command: `--notest`, `--disable-cache`, `--sandbox` (a directory image, for a node that cannot mount a SIF), Apptainer's `--ignore-subuid --ignore-fakeroot-command` (no root emulation at all). |
| Environment commands | Empty finds the runtime itself (the step's PATH, the usual install directories, the login shell's PATH, the known modules); otherwise the commands that provide one or set a proxy, one per line, run before every step. |
| Cache directory | The downloaded image layers. Empty: `.cache` under the image directory; a shared filesystem is fine. |
| Build scratch directory | Where the build unpacks the image, with room for the uncompressed image. Empty: the first of `TMPDIR`, `/tmp`, `/var/tmp` and `/dev/shm` that is writable, not mounted `noexec` and on a local disk. |

## Root emulation

An unprivileged `build` has to run the `%post` section as something that can write the
image's root filesystem, and the runtimes differ:

- **Apptainer** (1.1 and later) builds unprivileged by default: with a `subuid` range
  for the user it maps that range (`--fakeroot`); without one it tries the `fakeroot`
  command, then a single-user root-mapped namespace. On gcpsmall (Apptainer 1.4.5,
  `subuid` configured) `pip install`, `dnf install` and `gcc` in `%post` all build with
  the box off, with it on, and even with `--ignore-subuid --ignore-fakeroot-command`
  (verified 2026-10-21).
- **SingularityCE** has no cascade: as a non-root user it refuses a definition file
  outright (`--remote, --fakeroot, or the proot command are required to build this
  source as a non-root user`, awssmall 4.5.1, 2026-10-21) unless `--fakeroot` is
  passed with a `subuid` range the site configured, or `proot` is on PATH (4.1 and
  later). With the box off the workflow therefore adds `--fakeroot` for SingularityCE
  when the user has a range and says so; without a range or `proot` the build fails
  and the error names the cause. The Prepare step prints the range and `proot`.
- **With a `subuid` mapping the build scratch must be a local disk.** Apptainer's
  admin guide says a `--fakeroot` build cannot use NFS, Lustre, GPFS or PanFS as
  `TMPDIR`, and the failure is `packer failed to pack: while unpacking tmpfs: error
  unpacking rootfs: mkdir rootfs: ... no such file or directory` right after the
  layers were copied (Nautilus, 2026-10-21, with the scratch under the home
  directory). The layer cache has no such restriction. And Apptainer refuses a
  scratch mounted `noexec` (`'noexec' mount option set on /tmp, temporary root
  filesystem won't be usable at this location`, FRAN, 2026-10-21). That is why the
  scratch is a separate input from the cache and, left empty, is chosen among
  `TMPDIR`, `/tmp`, `/var/tmp` and `/dev/shm` by those two checks.

## A site whose proxy re-signs HTTPS

On a DSRC network the login node reaches the internet through a proxy that re-signs
HTTPS with the site's own certificate authority. The node trusts it, so the image
pull in the build works; a container's own CA bundle does not, so `pip`, `dnf`, `apt`,
`curl` or `git` inside `%post` fail with `CERTIFICATE_VERIFY_FAILED: unable to get
local issuer certificate` (FRAN, 2026-10-21, `pip install` in the default
definition; the `siteca` form passed there on 2026-10-22). Apptainer cannot bind a host file onto a path the image lacks, and
`%post` inherits nothing from the host environment (both verified on gcpsmall), so
the definition has to carry the bundle in. The workflow makes that one line: the
build runs in the job directory, where Prepare copies the node's bundle as
`site-ca-bundle.crt` (the first of `/etc/pki/tls/certs/ca-bundle.crt`,
`/etc/ssl/certs/ca-certificates.crt`, `/etc/ssl/ca-bundle.pem`, ... that exists;
the report says which), and `%files` resolves a relative source against that
directory:

```
%files
    site-ca-bundle.crt /etc/pw-site-ca.crt

%post
    export SSL_CERT_FILE=/etc/pw-site-ca.crt PIP_CERT=/etc/pw-site-ca.crt REQUESTS_CA_BUNDLE=/etc/pw-site-ca.crt CURL_CA_BUNDLE=/etc/pw-site-ca.crt GIT_SSL_CAINFO=/etc/pw-site-ca.crt
    pip install ...
```

That covers Python, `pip`, `requests`, `curl` and `git`. A package manager reads the
image's trust store instead, so for it the bundle goes into the store: on a Rocky or
RHEL image `%files site-ca-bundle.crt /etc/pki/ca-trust/source/anchors/pw-site-ca.crt`
and `update-ca-trust` first thing in `%post`; on Debian or Ubuntu
`%files site-ca-bundle.crt /usr/local/share/ca-certificates/pw-site-ca.crt` and
`update-ca-certificates`. The `siteca` test definitions (Tests, below) are both
recipes. The host bundle holds the public authorities too, so a definition written
this way builds the same on a site without interception.

## A node that cannot mount a SIF

Running a SIF needs the kernel's `squashfs` or, for an unprivileged mount,
`squashfuse`. A STIG-hardened image disables the module with an
`install squashfs /bin/false` rule in `/etc/modprobe.d` (awssmall on activate.hpc.mil
and awsstig on activate.parallel.works, 2026-10-22). There the build works and
`exec` of the SIF fails with `squashfs filesystem seems not enabled and/or supported
by your kernel`. The Prepare step's `squashfs` line names the rule, and a warning
before the build says the test will fail. The image itself is fine and runs on any
node that can mount it.

To run on such a node, build a sandbox: `--sandbox` in the extra options writes the
image as a directory, which `exec` and `run` use without mounting anything. It is
larger on disk and many files instead of one, so it is the fallback for those
nodes, not the default. The `python-numpy-sandbox` test definition is the recipe.

## Other systems

Nothing in the workflow is specific to one system: the runtime comes from the
environment commands, or from PATH and the known modules when they are left empty.

| System | Runtime | Environment commands | Verified |
|---|---|---|---|
| gcpsmall (Google cluster of activate.parallel.works) | Apptainer 1.4.5 on PATH, `subuid` configured, no proxy | empty | 2026-10-21 and 2026-10-22, the seven `gcpsmall-login-*` definitions |
| awsstig (STIG-hardened AWS cluster of activate.parallel.works) | SingularityCE 4.5.1 in `/usr/local/bin`, `subuid` range (the workflow adds `--fakeroot`); `/tmp`, `/var/tmp` and `/dev/shm` all mounted `noexec`, so the scratch falls back to the cache directory; `squashfs` disabled by `install squashfs /bin/false`, no `squashfuse`: the same restrictions as the HSP systems | empty | 2026-10-22: `python-numpy-auto` builds and fails the test on the SIF mount (a finding); `python-numpy-sandbox-auto` passes |
| Nautilus (Navy DSRC) | Apptainer 1.3.6 on PATH, `subuid` mapping, reaches Docker Hub; home is a network filesystem, so the build scratch must stay on the local disk (the default) | empty | 2026-10-21, `python-numpy-auto` and `rocky9-mpich-fakeroot`, by hand on the platform |
| FRAN (ARL DSRC) | Apptainer 1.5.3 in `/opt/apptainer/bin` (`singularity` is its alias there), added to PATH by the login profile only; `/tmp` is mounted `noexec`, the scratch fell back to the cache directory on the home filesystem and the unpack worked there; HTTPS is re-signed by the site's proxy, so a `%post` that downloads needs the node's CA bundle (above) | empty | 2026-10-21: the default definition builds up to `pip install`, which fails on the certificate (a finding, kept as a test). 2026-10-22: `python-numpy-siteca-auto` passed by hand on the platform; `rocky9-gcc-siteca-fakeroot` failed once fetching `rockylinux:9` (the manifest request closed with `EOF` after 60 s; the same request answers in 0.1 s from awsstig), so the fetch is now retried |
| awssmall (AWS cluster of activate.hpc.mil) | SingularityCE 4.5.1 in `/usr/local/bin`, which the step's PATH lacks; builds with `--fakeroot` (the user has a `subuid` range, the workflow adds the flag); the node cannot mount a SIF: its kernel has no `squashfs` and there is no `squashfuse`, so a built image does not run there | empty | 2026-10-21 and 2026-10-22: `python-numpy-auto` builds in 43 to 48 s and fails the test command on the SIF mount, named by the workflow; a finding for the cluster's image (enable `squashfs` or install `squashfuse`). 2026-10-22: `python-numpy-sandbox-auto` passed by hand on the platform |

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
    "cache_dir": "",
    "tmp_dir": ""
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
build.log          the build's output (build.attempt<N>.log: a base-image fetch that was retried)
test-command.txt   the test command, test.out its output
logs/build/step_N/step.out   the step traces (::error lines say why a run failed)
```

The image is at `<image directory>/<image file name>`, the layers at
`<cache directory>/cache/`; the build scratch (`build-temp-*` under the scratch
directory) is removed when the build ends. From anywhere: `pw workflows runs errors <slug>` and
`pw workflows runs logs <slug>`.

## Troubleshooting

A failing run is first of all a finding about the cluster, which is what a PROBE test
is for: a test keeps the definition and options its inputs were submitted with, and a
working alternative is a second test, not a change to the first.

- **`No container runtime found`** in Prepare: nothing on the step's PATH (printed
  in the report), in the usual install directories, on a login shell's PATH, or in
  the known modules. `which apptainer` in a login shell says where the site keeps
  it; put that in the environment commands as `export PATH=<directory>:${PATH}`,
  or the site's `module load singularity/<version>` (`module avail singularity`
  lists the name). A module directory a login-only profile adds goes in as
  `module use <directory>` before the `module load`. FRAN and awssmall (2026-10-21)
  were this case before the login-shell lookup existed: their runtime sits in a
  directory only the login profile adds.
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
- **`error unpacking rootfs: mkdir rootfs: ... no such file or directory`** right
  after the layers were copied: the build scratch is on a network filesystem and the
  build runs with a `subuid` mapping (Root emulation, above). The Prepare step warns
  about it before the build. Set the build scratch directory to a local disk.
- **`'noexec' mount option set on <dir>, temporary root filesystem won't be usable`**:
  Apptainer refuses the scratch. The Prepare step lists the options it checked
  (`scratch options:`) with `noexec` marked; set the build scratch directory to one
  mounted without it, on a local disk.
- **`--remote, --fakeroot, or the proot command are required to build this source
  as a non-root user`**: SingularityCE without a `subuid` range for the user and
  without `proot` (Root emulation, above). Ask the site for either; a definition
  whose `%post` needs no root can bootstrap from a prebuilt image instead.
- **`conveyor failed to get: ... EOF`** (or a reset, a timeout, `toomanyrequests`)
  before `%post` ran: the connection to the registry failed on the way. The build
  retries it twice; when all three attempts fail the route itself is broken (a proxy
  that drops the connection, a rate limit). Run again later, set the proxy in the
  environment commands if the site needs one, or bootstrap from an image already on
  the system (`Bootstrap: localimage`).
- **`CERTIFICATE_VERIFY_FAILED` or `unable to get local issuer certificate` inside
  `%post`** while the image pull worked: the site's proxy re-signs HTTPS. Copy the
  node's bundle in (A site whose proxy re-signs HTTPS, above).
- **The build passes and the test fails with `squashfs filesystem seems not enabled
  and/or supported by your kernel`**: the node cannot mount a SIF (the Prepare
  step's `squashfs` line, usually a STIG rule that disables the module). The image is
  fine; it runs once the site enables `squashfs` or installs `squashfuse`, or build
  with `--sandbox` (A node that cannot mount a SIF, above).
- **`No space left on device` during the build**: the scratch filesystem is full (the
  build unpacks the whole image there). Set the build scratch directory to a larger
  local filesystem; the cache directory holds the compressed layers and can stay.
- **`failed to execute %test script`**: the definition's own test failed inside the
  build, so the image was not written. Fix the definition, or pass `--notest` to
  look at the image anyway.
- **The build passes and the Test step fails**: the finished image does not run on
  the login node the way the build's sandbox did (a missing `/bin/sh`, a command not
  on the image's PATH, a node that cannot mount a SIF). The output above the error
  says which.

## Tests

A test is named after the cluster, `login`, the definition and the root emulation it
was submitted with: `<cluster>-login-<definition>-<auto|fakeroot|norootemulation>`,
or what else it varies (`workdir`, `sandbox`).
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
| `rocky9-mpich` | MPICH from Rocky 9's AppStream and an MPI hello world compiled in `%post`; two ranks run inside the finished image with the container's own `mpirun`, Allreduce checked: the container an HPC job would run |
| `multistage` | a two-stage definition: compiled with gcc in a `rockylinux:9` stage, copied with `%files from` into a `rockylinux:9-minimal` image without the compiler |
| `python-numpy-workdir` (DSRC systems) | the default definition with the image and cache under `$WORKDIR`, where a DSRC keeps large files; shows whether a workflow step sees `WORKDIR` |
| `python-numpy-siteca` | the default definition with the node's CA bundle copied in and `pip` pointed at it: the form for a site whose proxy re-signs HTTPS |
| `python-numpy-sandbox` | the default definition built with `--sandbox`, a directory image: the form for a node that cannot mount a SIF |
| `rocky9-gcc-siteca` | `rocky9-gcc` with the bundle added to the image's trust store (`update-ca-trust`) before `dnf`, submitted with `--fakeroot` |

The activate.parallel.works tests are how the workflow is tested from the cloud before
a run on HSP. The seven `gcpsmall-login-*` definitions passed through
`python3 -m probe run` on 2026-10-21 and 2026-10-22. The `awsstig-login-*` ones run on
a STIG-hardened image that has the same restrictions as the HSP systems (`noexec`
scratch, no SIF mount, SingularityCE), so it is where a change is tried first now.
