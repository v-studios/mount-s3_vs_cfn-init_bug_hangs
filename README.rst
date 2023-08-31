==================================
 mount-s3 vs. cfn-init: Bug Hangs
==================================

We deploy an EC2 and run CloudFormation Init to install ``mount-s3``
then mount an S3 bucket. The entire ``cfn-init`` script hangs at this
point -- even though the mount succeeds -- preventing the execution
subsequent ``commands`` and ``services``.

This repo minimally recreates this issue.

Reproduce
=========

Deploy the stack::

  make deploy

It's just a wrapper for a CloudFormation deployment command.

When done, use the AWS console (or ``make connect``) to get a shell on
the instance.

Use the following to verify the clout-init worked::

  sh-5.2$ sudo bash
  [root@ip-10-192-10-136 bin]# cat /var/log/cloud-init-output.log
  ...
  nothing to do.
  Complete!
  + cfn-init -v --region us-east-1 --stack chris-s3mount-bug --resource Ec2Instance

Then check the ``cfn-init`` and notice that it stops reporting during
the ``mount-s3`` step::

  [root@ip-10-192-10-136 bin]# tail /var/log/cfn-init-cmd.log
  2023-08-31 12:23:44,726 P2110 [INFO]
  2023-08-31 12:23:44,726 P2110 [INFO]    Installed:
  2023-08-31 12:23:44,726 P2110 [INFO]      fuse-2.9.9-13.amzn2023.0.2.x86_64   fuse-common-3.10.4-1.amzn2023.0.2.x86_64
  2023-08-31 12:23:44,726 P2110 [INFO]      mount-s3-1.0.0-1.x86_64
  2023-08-31 12:23:44,726 P2110 [INFO]
  2023-08-31 12:23:44,726 P2110 [INFO]    Complete!
  2023-08-31 12:23:44,726 P2110 [INFO] ------------------------------------------------------------
  2023-08-31 12:23:44,726 P2110 [INFO] Completed successfully.
  2023-08-31 12:23:44,728 P2110 [INFO] ============================================================
  2023-08-31 12:23:44,728 P2110 [INFO] Command 91_mount_s3

We can see the mount worked, and we've got bucket contents::

  root@ip-10-192-10-136 bin]# ls -al /s3
  total 3219531
  drwxr-xr-x.  2 root root          0 Aug 31 12:23 .
  dr-xr-xr-x. 19 root root        247 Aug 31 12:23 ..
  -rw-r--r--.  1 root root 3278958750 Aug 25 15:36 First-8K-Video-from-Space.mp4
  drwxr-xr-x.  2 root root          0 Aug 31 12:23 image
  -rw-r--r--.  1 root root   17839845 Aug 25 00:46 video-18mb.mp4

  [root@ip-10-192-10-136 bin]# mount |grep s3
  mountpoint-s3 on /s3 type fuse (ro,nosuid,nodev,noatime,user_id=0,group_id=0,default_permissions)

But it never executed the ``echo``, or the next step which ``touch``es a file in S3::

  root@ip-10-192-10-136 bin]# ls -l /tmp
  total 0
  drwx------. 3 root root 60 Aug 31 12:23 systemd-private-977bba92f1be4a438aef021f05a6e4ef-chronyd.service-qS8azV
  drwx------. 3 root root 60 Aug 31 12:23 systemd-private-977bba92f1be4a438aef021f05a6e4ef-dbus-broker.service-mykVZM
  drwx------. 3 root root 60 Aug 31 12:23 systemd-private-977bba92f1be4a438aef021f05a6e4ef-policy-routes@enX0.service-R0vm6v
  drwx------. 3 root root 60 Aug 31 12:23 systemd-private-977bba92f1be4a438aef021f05a6e4ef-systemd-logind.service-YiXZla
  drwx------. 3 root root 60 Aug 31 12:23 systemd-private-977bba92f1be4a438aef021f05a6e4ef-systemd-resolved.service-4AtdgY

It also never complains about trying to ``enable`` a ``service`` that
we haven't installed, so it's not getting that far. We can see that in
the ``cfn-init/resume_db.json`` file::

  [root@ip-10-192-10-118 bin]# python3 -mjson.tool /var/lib/cfn-init/resume_db.json
  {
      "metadata": {
          "AWS::CloudFormation::Init": {
              "config": {
                  "services": {
                      "sysvinit": {
                          "docker": {
                              "ensureRunning": "true",
                              "enabled": "true"
                          }
                      }
                  },
                  "commands": {
                      "91_mount_s3": {
                          "command": "mkdir /s3\necho \"About to mount-s3...\"\nmount-s3 --read-only chris-serverless-vmedia /s3\necho \"Done with mount-s3.\"\n"
                      },
                      "10_install_mount_s3": {
                          "command": "yum install -y https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm"
                      },
                      "99_zzz": {
                          "command": "touch /tmp/99_zzz\necho \"99_zzz Will you ever see me?\"\n"
                      }
                  }
              }
          }
      }
  }

It doesn't hang when I invoke it on the CLI inside the container::

  [root@ip-10-192-10-136 bin]# time mount-s3 chris-serverless-vmedia /mnt
  bucket chris-serverless-vmedia is mounted at /mnt

  real    0m0.105s
  user    0m0.000s
  sys     0m0.005s

Both mountpoints have the same native modes if I ``umount`` them::``

  [root@ip-10-192-10-136 bin]# umount /mnt
  [root@ip-10-192-10-136 bin]# umount /s3
  [root@ip-10-192-10-136 bin]# ls -ald /mnt /s3
  drwxr-xr-x. 2 root root 6 Jan 30  2023 /mnt
  drwxr-xr-x. 2 root root 6 Aug 31 12:23 /s3

So why is the ``mount-s3`` hanging in ``cfn-init``?
