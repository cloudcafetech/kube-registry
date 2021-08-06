# kube-registry
Kubernetes Registry using Jfrog

- Setup

```
wget https://raw.githubusercontent.com/cloudcafetech/kube-registry/main/k8s-setup.sh
chmod +x k8s-setup.sh
./k8s-setup.sh k3d
```

- EULA

```curl -XPOST -vku admin:password https://jfregistry.172.31.44.213.nip.io/artifactory/ui/jcr/eula/accept```

[Ref#1](https://next.nutanix.com/community-blog-154/deploying-jfrog-container-registry-on-nutanix-karbon-33739)
