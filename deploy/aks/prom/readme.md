The configuration was adopted from this (repo)[https://github.com/giantswarm/prometheus]

to deploy:
``` bash
kubectl apply --filename deploy/aks/prom/manifests-all.yaml
```

to remove:
``` sh
kubectl delete namespace monitoring
```