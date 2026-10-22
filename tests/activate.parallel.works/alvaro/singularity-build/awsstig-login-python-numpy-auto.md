# awsstig-login-python-numpy-auto

The form's default on the STIG-hardened AWS cluster: SingularityCE 4.5.1, `--fakeroot` added by the workflow, every local scratch option mounted `noexec` (the build falls back to the cache directory), and `squashfs` disabled by a modprobe rule. The build passes and the test fails on the SIF mount: a finding about the image, recorded as such until the cluster can mount a SIF.
