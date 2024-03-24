+++
title = 'Kubernetes Postgres Backups'
date = 2024-03-24
draft = false
tags = ["k3s", "k8s", "kubernetes", "postgresql", "backups"]
toc = true
summary = "Automatic backups of PostgreSQL hosted in kubernetes"
+++

Services running in kubernetes backed by a datastore also in kubernetes require backups just like everything else. This post describes one way to make automated backups for a PostgreSQL DB in kubernetes.

With a few modifications, the approach detailed here can be applied to other databases that are not Postgres.

## Requirements

1. Backups must be taken regularly, once a week is fine for this example
2. Backups must be stored on a separate host, as part of a 3-2-1 strategy.
    * A 3-2-1 backup strategy is having 3 copies of data, on at least two types of media, with at least one of those copies being offsite.
    For this post I'll be using my NAS as a second copy. The NAS will have several backups at any given time. The offsite backup is out of scope for this post.
3. Obviously no secrets should be stored in git
4. Backups should be encrypted at rest

## Out Of Scope

* N backups are kept at any given time. I have other existing automation that handles this.
* Creating kubernetes secrets used in the backup. This post assumes the secrets are either already created, or created as part of your deploy job.

## The Plan

1. Create a new image based on [bitnami's postgresql](https://github.com/bitnami/charts/tree/main/bitnami/postgresql) image containing a shell script to dump, encrypt, and compress the a database
2. Create a kubernetes [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) to periodically backup the data
3. Manually test to verify data is backed up

## The Backup Shell Script

This is a quick bash script I've put together for taking backups. The script assumes two environment variables have been set.

* PGPASSWORD - used to access PostgreSQL database.
* ENCRYPT_PASSWORD - used to encrypt the dump with a password. With minor alterations to the script a pubkey could be used instead of a password. I chose a password because laziness. I mean seriously, I skipped an entire openssl command here.

If you run this script on something that is not ephemeral, you'll want to update the script to remove `${TMP_OUT}` since that's an unencrypted copy of a supposedly important database.

```bash
#!/bin/bash
set -e

TMP_OUT=/tmp/dump.sql

Help() {
    echo "Takes a backup of a postgresql database."
    echo
    echo "PGPASSWORD should be set via environment variable"
    echo "ENCRYPT_PASSWORD should be set via environment variable"
    echo
    echo "syntax ./backup.sh -H postgres_host:port -d database_name -u database_user -o /path/to/output/directory/"
    echo
    echo args:
    echo "h     Displays this help message."
    echo "H     The host:port at which to reach the postgres server."
    echo "d     The database to backup."
    echo "u     The database user to user. ENCRYPT_PASSWORD must be set."
    echo "o     The directory to write the backup to. Backup file will be named in YYYY-MM-DD-database_name.sql.gz.enc"
}

Die() {
    echo >&2 "$@"
    echo
    Help
    echo
    exit 1
}

ParseArgs() {
    while getopts "h:H:d:u:o:" option; do
       case $option in
            h) # display Help
                Help
                exit;;
            H)
                DB_HOST=${OPTARG};;
            d)
                DB=${OPTARG};;
            u)
                DB_USER=${OPTARG};;
            o)
                OUT_DIR=${OPTARG};;
            \?) # Invalid option
                echo "Error: Invalid option"
                Help
                exit;;
       esac
    done
}

ValidateArgs() {
    ! [[ -z ${DB_HOST} ]] || Die "missing required arg -H"
    ! [[ -z ${DB} ]] || Die "missing required arg -d"
    ! [[ -z ${DB_USER} ]] || Die "missing required arg -u"
    ! [[ -z ${OUT_DIR} ]] || Die "missing required arg -o"
    ! [[ -z ${PGPASSWORD} ]] || Die "PGPASSWORD env var must be set"
    ! [[ -z ${ENCRYPT_PASSWORD} ]] || Die "ENCRYPT_PASSWORD env var must be set"
}

DumpDB() {
    pg_dump -U ${DB_USER} -h ${DB_HOST} ${DB} > ${TMP_OUT}
}

EncryptDump() {
    mkdir -p ${OUT_DIR}/${DB}
    gzip -c ${TMP_OUT} \
        |  openssl enc -pbkdf2 \
              -salt \
              -out ${OUT_DIR}/${DB}/$(date +%F)-${DB}.sql.gz.enc \
              -pass pass:${ENCRYPT_PASSWORD}
}

ParseArgs $@
ValidateArgs
DumpDB
EncryptDump
```

## The Image

The Dockerfile here is very simple.

```Dockerfile
FROM docker.io/bitnami/postgresql:16.2.0-debian-12-r8

COPY backup.sh /backup.sh
```

## The CronJob Definition

Below is a CronJob used with an exampled application named "important-application-here".

Several small pieces are left as an exercise for the reader.

* The image is left as `image: <Where-You-Host-Your-Image>:latest`. You'll want to update that with the location of the image generated from the Dockerfile above.
* For my purposes the volume `important-application-here-postgres-backup-nfs-claim` is assumed to already exist. I've used NFS mounts to mount my DB backup share on my NAS.
* Creating secrets will need to be done.

You may also want to update the schedule. Having many services run their backups at the same time could cause an issue, but really that's a problem for another day.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: important-application-here-backup
  namespace: important-application-here
spec:
  schedule: "0 0 * * 0"
  jobTemplate:
    spec:
      template:
        spec:
          imagePullSecrets:
          - name: regcred
          containers:
          - name: postgresbackup
            image: <Where-You-Host-Your-Image>:latest
            imagePullPolicy: Always
            env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: important-application-here-postgresql
                  key: password
            - name: ENCRYPT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: backup-encrypt
                  key: ENCRYPT_PASSWORD
            command:
            - /backup.sh
            args:
            - -H
            - important-application-here-postgresql.important-application-namespace.svc.cluster.local
            - -d important-application-here
            - -u important-application-here
            - -o
            - /backups
            volumeMounts:
            - name: backup-dir
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-dir
            persistentVolumeClaim:
              claimName: important-application-here-postgres-backup-nfs-claim
```

## Verification

Once the CronJob has been deployed, you'll want to verify it works. No one wants to wait up to a week to see if their yaml skills are up to par, so create a manual run.

```bash
# starts a job in the important-application-here namespace
kubectl create job --from=cronjob/important-application-here-backup manual-backup -n important-application-here
```

Verify that your backup shows up in the expected location, and that is has the expected contents! I mounted the backup NFS on /mnt/db_backups

```bash
cd /mnt/db_backups
openssl enc -d -pbkdf2 -in 2024-03-24-name-of-db-here.sql.gz.enc -k TopSecretPasswordHere | gzip -d
```

A smart person would also verify that the service can be restored from backup. That process depends on the application being backed up. Don't wait until you need the backup to verify your recovery process works. If you don't verify your recovery process, you do not have a recovery process.
