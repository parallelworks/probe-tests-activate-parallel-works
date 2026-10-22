# gcpsmall-login-multistage-auto

A two-stage definition: a program compiled with gcc in a `rockylinux:9` build stage, copied with `%files from` into a `rockylinux:9-minimal` final image with no compiler; the runtime's own root emulation (the box off).
