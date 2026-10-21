#!/bin/bash
# The manual check behind the mpi-hello workflow (../yamls/hsp.yaml): run it on the
# Nautilus login node and paste the whole output back.
#
#   bash nautilus-check.sh                  system facts, the MPI module, the hello world on the login node
#   bash nautilus-check.sh --account ACCT   the same, then one SLURM job that runs the hello world with
#                                           mpirun and with srun on 2 nodes, and prints its output
#
# Options (the defaults match ../tests/hsp/nautilus-compute.json):
#   --account ACCT    SLURM account (--account); the job is submitted only when given
#   --qos QOS         --qos (default standard)
#   --constraint C    --constraint (default standard; '' for none)
#   --nodes N         --nodes (default 2)
#   --ppn M           --ntasks-per-node, and the rank count on the login node (default 2)
#   --time T          --time (default 00:10:00)
#   --wait MIN        minutes to wait for the job (default 20); after that it is left queued
#   --module MOD      the MPI module (default mpich/gnu/3.3.2)
#
# Nothing is installed or changed outside ${HOME}/pw/tests/mpi-hello/check.
set -o pipefail

ACCOUNT=""
QOS="standard"
CONSTRAINT="standard"
NODES=2
PPN=2
TIME="00:10:00"
WAIT_MIN=20
MPI_MODULE="mpich/gnu/3.3.2"
while [ $# -gt 0 ]; do
    case "$1" in
        --account)    ACCOUNT="$2"; shift 2 ;;
        --qos)        QOS="$2"; shift 2 ;;
        --constraint) CONSTRAINT="$2"; shift 2 ;;
        --nodes)      NODES="$2"; shift 2 ;;
        --ppn)        PPN="$2"; shift 2 ;;
        --time)       TIME="$2"; shift 2 ;;
        --wait)       WAIT_MIN="$2"; shift 2 ;;
        --module)     MPI_MODULE="$2"; shift 2 ;;
        -h|--help)    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1 (see --help)"; exit 2 ;;
    esac
done

section() { echo; echo "===== $* ====="; }
# show <timeout-s> '<command line>': prints the command, runs it, never stops the script
show() {
    local t="$1"; shift
    echo "\$ $*"
    timeout "${t}" bash -c "$*" 2>&1 || echo "(exit $?)"
}

section "1. System ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
show 10 'hostname; whoami; echo HOME=$HOME; echo WORKDIR=${WORKDIR:-unset}; echo PROJECTS_HOME=${PROJECTS_HOME:-unset}'
show 10 'grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release; uname -r; nproc; lscpu | grep -E "Model name|^CPU\(s\)"'
show 10 'python3 --version; git --version; command -v curl wget tar timeout setsid'
show 20 'command -v pw && pw --version && pw context current'
show 20 'curl -sS -m 10 -o /dev/null -w "github.com HTTP %{http_code}\n" https://github.com'
show 10 'df -h "$HOME" | tail -n 1'

section "2. Modules"
# the initialization the workflow does in a non-login shell before the form's commands
if command -v module > /dev/null 2>&1; then
    echo "module is already defined in this shell"
else
    for f in /etc/profile.d/modules.sh /etc/profile.d/lmod.sh \
             /usr/share/lmod/lmod/init/bash /usr/share/Modules/init/bash; do
        if [ -r "${f}" ]; then
            echo "module initialized from ${f}"
            source "${f}"
            break
        fi
    done
fi
if ! command -v module > /dev/null 2>&1; then
    echo "WARNING: module is not available in this shell (no init file found)"
fi
echo "\$ module --version"; module --version 2>&1 | head -n 3
echo "\$ module avail mpi"; module avail mpi 2>&1
echo "\$ module show ${MPI_MODULE}"; module show "${MPI_MODULE}" 2>&1 | head -n 40

section "3. SLURM"
show 20 'sinfo -s'
show 20 'sinfo -o "%P %a %l %D %t %f" | head -n 30'
show 20 'scontrol show config | grep -i -E "^(ClusterName|SelectType|MpiDefault|MpiParams|KillWait|SchedulerType|PrologFlags)"'
show 20 "sacctmgr show assoc where user=${USER} format=cluster,account,partition,qos,defaultqos,maxjobs -P"
show 20 'sacctmgr show qos format=name,maxwall,maxtrespu,maxjobspu,priority,flags -P'
show 20 "squeue -u ${USER}"
show 30 'command -v show_usage && show_usage'

section "4. MPI hello world on the login node (${MPI_MODULE}, ${PPN} ranks)"
dir="${HOME}/pw/tests/mpi-hello/check"
mkdir -p "${dir}" && cd "${dir}" || exit 1
echo "working in ${dir}"
cat > mpi_hello.c <<'EOF'
/* Every rank says hello with its processor name, then the ranks sum their
   numbers with MPI_Allreduce: a collective that fails when the ranks cannot
   talk to each other, which hello lines alone would not show. */
#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv) {
    int rank, size, len, sum = 0, expected;
    char name[MPI_MAX_PROCESSOR_NAME];
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &len);
    printf("Hello world from processor %s, rank %d out of %d processors\n", name, rank, size);
    fflush(stdout);
    MPI_Allreduce(&rank, &sum, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    expected = size * (size - 1) / 2;
    if (rank == 0) {
        printf("Allreduce of the ranks: %d (expected %d): %s\n", sum, expected,
               sum == expected ? "OK" : "WRONG");
        fflush(stdout);
    }
    if (sum != expected) {
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    MPI_Finalize();
    return 0;
}
EOF
echo "\$ module load ${MPI_MODULE}"; module load "${MPI_MODULE}" 2>&1
show 10 'command -v mpicc mpirun mpiexec srun'
show 10 'mpichversion | head -n 4'
show 10 'mpicc -show'
show 10 'mpirun --version 2>&1 | head -n 3'
echo "\$ mpicc -O2 -o mpi_hello mpi_hello.c"
if mpicc -O2 -o mpi_hello mpi_hello.c; then echo "compiled"; else echo "COMPILE FAILED"; fi
show 90 "mpirun -np ${PPN} ./mpi_hello"

section "5. SLURM job"
if [ -z "${ACCOUNT}" ]; then
    echo "No --account given: the SLURM job is skipped."
    echo "Rerun with --account <account> [--qos standard] [--constraint standard] to submit one."
    exit 0
fi
cat > job.sh <<EOF
#!/bin/bash
#SBATCH --job-name=mpi-hello-check
#SBATCH --account=${ACCOUNT}
#SBATCH --qos=${QOS}
#SBATCH --cpus-per-task=1
#SBATCH --nodes=${NODES}
#SBATCH --ntasks-per-node=${PPN}
#SBATCH --time=${TIME}
#SBATCH --chdir=${dir}
#SBATCH -o ${dir}/job.%j.out
#SBATCH -e ${dir}/job.%j.out
EOF
if [ -n "${CONSTRAINT}" ]; then
    echo "#SBATCH --constraint=${CONSTRAINT}" >> job.sh
fi
echo "MPI_MODULE=${MPI_MODULE}" >> job.sh
cat >> job.sh <<'EOF'
set -o pipefail
if ! command -v module > /dev/null 2>&1; then
    for f in /etc/profile.d/modules.sh /etc/profile.d/lmod.sh \
             /usr/share/lmod/lmod/init/bash /usr/share/Modules/init/bash; do
        if [ -r "${f}" ]; then
            source "${f}"
            break
        fi
    done
fi
module load "${MPI_MODULE}"
echo "node $(hostname), SLURM job ${SLURM_JOB_ID} on ${SLURM_JOB_NODELIST}: ${SLURM_NTASKS} tasks on ${SLURM_JOB_NUM_NODES} nodes"
echo "mpirun: $(command -v mpirun)"
echo
echo "=== srun --mpi=list"
srun --mpi=list 2>&1
for launcher in "mpirun -np ${SLURM_NTASKS}" "srun --mpi=pmi2 -n ${SLURM_NTASKS}" "srun -n ${SLURM_NTASKS}"; do
    echo
    echo "=== ${launcher} ./mpi_hello"
    timeout 120 ${launcher} ./mpi_hello
    echo "=== exit $?"
done
EOF
echo "--- job.sh"; cat job.sh
echo "\$ sbatch job.sh"
out=$(sbatch job.sh 2>&1); echo "${out}"
jobid=$(echo "${out}" | awk '/Submitted batch job/ {print $4}')
if [ -z "${jobid}" ]; then
    echo "SUBMISSION FAILED"
    exit 1
fi
deadline=$(( $(date +%s) + WAIT_MIN * 60 ))
polls=0
while squeue -h -j "${jobid}" 2>/dev/null | grep -q .; do
    if [ "$(date +%s)" -ge "${deadline}" ]; then
        echo "job ${jobid} is still in the queue after ${WAIT_MIN} min:"
        squeue -j "${jobid}"
        echo "read its output later with: cat ${dir}/job.${jobid}.out   (scancel ${jobid} drops it)"
        exit 0
    fi
    polls=$(( polls + 1 ))
    if [ $(( polls % 4 )) -eq 1 ]; then
        echo "$(date +%H:%M:%S) job ${jobid}: $(squeue -h -j "${jobid}" -o '%T %r %N' 2>/dev/null)"
    fi
    sleep 15
done
show 20 "sacct -j ${jobid} -X --format=JobID,State,ExitCode,Elapsed,NodeList,QOS,Account,Partition -P"
echo "--- ${dir}/job.${jobid}.out"
cat "${dir}/job.${jobid}.out"
