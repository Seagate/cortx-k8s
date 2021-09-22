## Liveness probe

The kubelet uses liveness probes to know when to restart a container. For example, liveness probes could catch a deadlock, where an application is running, but unable to make progress. Restarting a container in such a state can help to make the application more available despite bugs.

The periodSeconds field specifies that the kubelet should perform a liveness probe every `5 seconds`. The initialDelaySeconds field tells the kubelet that it should wait `6 seconds` before performing the first probe. To perform a probe, the kubelet executes the command `cat /app/liveness.txt` in the target container. If the command succeeds, it returns 0, and the kubelet considers the container to be alive and healthy. If the command returns a non-zero value, the kubelet kills the container and restarts it.

This is the section where the liveness probe is configured:


```sh
livenessProbe:
  exec:
    command:
    - cat
    - /app/liveness.txt
  initialDelaySeconds: 6
  periodSeconds: 5
```

(See [deployment.yaml](./deployment.yaml) for full reference)


The output when logging the container looks like this:

```sh
Pod is alive! 🤠
      Counter: 41
      Random number: 2.
      ----------------------------------
Pod is alive! 🤠
      Counter: 42
      Random number: 2.
      ----------------------------------
Pod is alive! 🤠
      Counter: 43
      Random number: 9.
      ----------------------------------
It is going to crash ☹️ ...
Random number is 7!
```

## Readiness probe

Similarly to the Liveness probe, the Readiness probe is configured in this way:

```sh
readinessProbe:
  exec:
    command:
    - cat
    - /app/liveness.txt
  initialDelaySeconds: 5
```

The initialDelaySeconds field tells the kubelet that it should wait `5 seconds` before performing the readiness probe.


 ## PostStart and PreStop events

Kubernetes sends the postStart event immediately after a Container is started, and it sends the preStop event immediately before the Container is terminated.

 We have configured those events within the `deployment.yaml` file (See [deployment.yaml](./deployment.yaml) for full reference). 

 ```sh
lifecycle:
  postStart:
    exec:
      command: ["/bin/sh", "/app/postStart.sh"]
  preStop:
    exec:
      command: ["/bin/sh", "/app/preStop.sh"]
 ```

When the container is started, Kubernetes sends the postStart event and the `postStart.sh` script is executed:


```sh
# cat /app/postStart.sh
Preparing pod to start 💫
```

When the container is killed, Kubernetes sends the preStop event and the `preStop.sh` script is executed:

```sh
# cat /app/preStop.sh
Preparing pod to be terminated in 90 seconds... 💀
```