# awssmall-rocky9-260928-login-rocky9-mpich-fakeroot

`rockylinux:9` with MPICH from its AppStream and an MPI hello world compiled in `%post`, submitted with `--fakeroot`; two ranks run inside the finished image with the container's own `mpirun` and their Allreduce is checked.
