# Singularity build

Build a container image from a definition file on a cluster's login node, then run a
command inside it. The run passes only when the image builds **and** runs on that
node, so a failure tells you what the cluster is missing.

```
  you give                 the workflow, on the login node               you get
  ───────────────          ─────────────────────────────────             ──────────────────
  definition file   ──►    1  find apptainer or singularity       ──►    the image
  image name, dir          2  check the node: scratch space,             <dir>/<name>.sif,
  test command                root emulation, SIF mount, CA              or a directory
                           3  singularity build                          with --sandbox
                           4  singularity exec <image> <test>     ──►    pass, or fail
                                                                         with the reason
```

No scheduler job and no endpoint. Only the image and its layer cache stay behind.

## Run it

Run `yamls/hsp.yaml` on the platform and fill the form, or pass inputs like these:

```json
{
  "resource": "pw://<user>/<cluster>",
  "container": {
    "definition": "Bootstrap: docker\nFrom: python:3.12-slim\n\n%post\n    pip install --no-cache-dir numpy==2.3.3\n",
    "image_name": "python-numpy.sif",
    "output_dir": "${HOME}/pw/software/containers",
    "test_command": "python -c \"import numpy; print(numpy.__version__)\""
  },
  "build": { "fakeroot": false, "timeout_min": 30, "options": "", "environment": "", "cache_dir": "", "tmp_dir": "" }
}
```

```bash
pw workflows run /abs/path/yamls/hsp.yaml -i inputs.json
```

## The inputs that matter

| Input | Change it when |
|---|---|
| Definition file | Always: it is what gets built. The default is Python 3.12 with NumPy. |
| Image file name, directory | The image belongs somewhere other than `~/pw/software/containers/container.sif`, for example under `$WORKDIR`. |
| Test command | You want to prove something specific runs in the image. The default is `cat /etc/os-release`. |
| Extra build options | The node cannot mount a SIF (`--sandbox`), or you want to skip `%test` (`--notest`). |
| Environment commands | The site needs a `module load` or a proxy that the workflow does not find on its own. |

Scratch space, root emulation (`--fakeroot`) and retries of a dropped download are
handled for you. The form's other inputs override them.

## What each system needs

| System | Runtime | What to add |
|---|---|---|
| Nautilus | Apptainer 1.3.6 | Nothing |
| FRAN | Apptainer 1.5.3 | The site's CA certificate, when `%post` downloads anything (below) |
| awssmall, awsstig | SingularityCE 4.5.1 | `--sandbox`, because the node cannot mount a SIF |
| gcpsmall | Apptainer 1.4.5 | Nothing |

**FRAN re-signs HTTPS** through its proxy, so `pip` or `dnf` inside the build fail with
`CERTIFICATE_VERIFY_FAILED`. The workflow puts the node's CA bundle next to the
definition as `site-ca-bundle.crt`. Copy it in:

```
%files
    site-ca-bundle.crt /etc/pw-site-ca.crt

%post
    export SSL_CERT_FILE=/etc/pw-site-ca.crt PIP_CERT=/etc/pw-site-ca.crt
    export REQUESTS_CA_BUNDLE=/etc/pw-site-ca.crt CURL_CA_BUNDLE=/etc/pw-site-ca.crt GIT_SSL_CAINFO=/etc/pw-site-ca.crt
    pip install ...
```

For `dnf`, copy it to `/etc/pki/ca-trust/source/anchors/pw-site-ca.crt` instead, and run
`update-ca-trust` first in `%post`.

## When it fails

The run's error names the cause (`pw workflows runs errors <slug>`). The Prepare step
prints a report of everything the build depends on.

| Error | Meaning | What to do |
|---|---|---|
| No container runtime found | Not on PATH, in the usual directories, or in a module | Put `module load ...` or `export PATH=...` in Environment commands |
| `CERTIFICATE_VERIFY_FAILED` in `%post` | The site's proxy re-signs HTTPS | Copy the CA bundle in, as above |
| SIF mount, `squashfs ... not enabled` | The kernel cannot mount a SIF, a STIG setting | Add `--sandbox` |
| Base image fetch | The connection to the registry failed three times | Run again later, or set the site's proxy in Environment commands |
| Build scratch, `noexec` or `mkdir rootfs` | The scratch is mounted `noexec` or on a network filesystem | Set Build scratch directory to a local disk |
| Root emulation, `--fakeroot ... required` | No subuid range and no `proot` for the user | Ask the site for a subuid range |

A test that fails this way is a finding about the system. Keep it, and record the
working alternative as a second test.

## Tests

The tests are PROBE definitions in this repository, under
`tests/<platform>/<user>/singularity-build/`. Each is one JSON of inputs, with a `.md`
that says what it checks, named `<cluster>-login-<definition>-<variant>`.

| Definition | What it checks |
|---|---|
| `python-numpy` | `pip install` in `%post`, the form's default |
| `rocky9-gcc` | `dnf` and a compile, which need root in `%post` |
| `rocky9-mpich` | an MPI program running inside the image, on two ranks |
| `multistage` | a build in one stage that ships a slim one |
| `alpine` | a build with no root emulation at all |
| `*-siteca` | the CA certificate recipe |
| `*-sandbox` | a directory image, for nodes that cannot mount a SIF |
| `*-workdir` | the image under `$WORKDIR` |

How each step works, every site finding with its date, and the full troubleshooting
are in [DEVELOPER.md](DEVELOPER.md).
